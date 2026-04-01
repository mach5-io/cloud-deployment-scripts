#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
VALUES_DIR="$REPO_ROOT/values"

source "$SCRIPT_DIR/common.sh"

CONFIG_OVERRIDE=""
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

usage() {
  cat <<EOF
Usage: $0 [-v|--verbose] [--dry-run] [--config PATH]

Options:
  -v, --verbose    Print each command before execution.
  --dry-run        Only log what would run (implies verbose output).
  --config PATH    Load a custom configuration file instead of the default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      VERBOSE=true
      shift
      ;;
    --config)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --config" >&2
        usage
        exit 1
      fi
      CONFIG_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$CONFIG_OVERRIDE" ]]; then
  CONFIG_FILE="$CONFIG_OVERRIDE"
else
  CONFIG_FILE="$CONFIG_FILE_DEFAULT"
fi

load_config

if [[ "$VERBOSE" == true ]]; then
  set -x
fi

PORT_FORWARD_PID=""
STORE_ID=""
PORT_FORWARD_LOG=""

cleanup_port_forward() {
  if [[ -n "${PORT_FORWARD_LOG}" && -f "${PORT_FORWARD_LOG}" ]]; then
    rm -f "${PORT_FORWARD_LOG}"
  fi
}

trap cleanup_port_forward EXIT

ensure_namespace() {
  local namespace=$1
  if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    log "INFO" "Namespace '$namespace' already exists."
  else
    execute kubectl create namespace "$namespace"
  fi
}

helm_registry_login() {
  if [[ ! -f "$MACH5_READER_KEY_PATH" ]]; then
    echo "Reader key at '$MACH5_READER_KEY_PATH' not found" >&2
    return 1
  fi

  execute bash -c "cat \"$MACH5_READER_KEY_PATH\" | helm registry login \"$MACH5_ARTIFACT_REGISTRY_URL\" -u _json_key --password-stdin"
}

wait_for_mach5_pods() {
  log "INFO" "Waiting for Mach5 pods to report ready status."
  execute kubectl wait --for=condition=Ready pod --all -n mach5 --timeout=1200s
}

verify_mach5_pods_running() {
  log "INFO" "Verifying all Mach5 pods are in Running state."
  if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "Dry run enabled; skipping pod state verification."
    return 0
  fi

  local non_running
  non_running=$(kubectl get pods -n mach5 --no-headers | awk '$3 != "Running" {print $1 " (" $3 ")"}')
  if [[ -n "$non_running" ]]; then
    printf "ERROR: Found non-running pods in namespace 'mach5':\n%s\n" "$non_running" >&2
    return 1
  fi
}

start_port_forward() {
  local namespace=$1
  local service_name=$2
  local local_port=$3
  local remote_port=$4

  if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "Dry run enabled; skipping port-forward."
    return 0
  fi

  PORT_FORWARD_LOG=$(mktemp -t mach5-port-forward.XXXXXX.log)
  log "INFO" "Starting port-forward: svc/${service_name} ${local_port}:${remote_port}."
  kubectl -n "$namespace" port-forward "svc/${service_name}" "${local_port}:${remote_port}" >"$PORT_FORWARD_LOG" 2>&1 &
  PORT_FORWARD_PID=$!

  for _ in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${local_port}/" | grep -qE '^[1-5][0-9]{2}$'; then
      log "INFO" "Port-forward is ready on localhost:${local_port}."
      return 0
    fi
    sleep 1
  done

  echo "ERROR: Port-forward did not become ready within 30 seconds." >&2
  if [[ -f "$PORT_FORWARD_LOG" ]]; then
    echo "Port-forward log:" >&2
    cat "$PORT_FORWARD_LOG" >&2
  fi
  return 1
}

print_port_forward_help() {
  if [[ -z "${PORT_FORWARD_PID}" ]]; then
    return 0
  fi

  :
}

print_final_summary() {
  printf "\n"
  printf "======================= IMPORTANT: NEXT STEPS =======================\n"
  printf "Helm components deployed. Verify with:\n"
  printf "  helm list --all -n mach5\n\n"

  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    printf "Port-forward is running in the background (PID %s).\n" "${PORT_FORWARD_PID}"
    printf "Stop it with:\n"
    printf "  kill %s\n\n" "${PORT_FORWARD_PID}"
    printf "Recreate it with:\n"
    printf "  kubectl -n mach5 port-forward svc/%s %s:%s\n\n" \
      "$MACH5_NGINX_SERVICE_NAME" "$MACH5_STORE_LOCAL_PORT" "$MACH5_NGINX_PORT"
  fi

  printf "Mach5 Search Dashboards URL:\n"
  printf "  http://localhost:%s/warehouse/default/m5warehouse/dashboards/\n" "${MACH5_STORE_LOCAL_PORT}"
  printf "OpenSearch-compatible API URL:\n"
  printf "  http://localhost:%s/warehouse/default/m5warehouse/opensearch/\n" "${MACH5_STORE_LOCAL_PORT}"
  printf "======================================================================\n\n"
}

extract_store_id() {
  # Accepts JSON on stdin and returns the first id-like value found.
  # Tries keys: id, store_id, data.id, data.store_id.
  local payload
  payload=$(cat)
  if [[ -z "$payload" ]]; then
    return 1
  fi

  # Strip newlines/spaces to simplify regex matching.
  local compact
  compact=$(printf '%s' "$payload" | tr -d '\n' | tr -d '\r')

  local id
  id=$(printf '%s' "$compact" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [[ -z "$id" ]]; then
    id=$(printf '%s' "$compact" | sed -n 's/.*"store_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi
  if [[ -n "$id" ]]; then
    printf '%s' "$id"
    return 0
  fi
  return 1
}

create_store() {
  log "INFO" "Creating Mach5 store '${MACH5_STORE_NAME}'."
  if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "Dry run enabled; skipping store creation."
    return 0
  fi

  local store_response
  store_response=$(curl -sS -X PUT "http://localhost:${MACH5_STORE_LOCAL_PORT}/apis/stores/${MACH5_STORE_NAME}" \
    -H "Content-Type: application/json" \
    -d "{
      \"account\": \"${STORAGE_ACCOUNT_NAME}\",
      \"bucket\": \"${STORAGE_CONTAINER_NAME}\",
      \"prefix\": \"${MACH5_STORE_PREFIX}\",
      \"type\": \"${MACH5_STORE_TYPE}\"
    }")

  STORE_ID=$(printf '%s' "$store_response" | extract_store_id || true)
  if [[ -z "$STORE_ID" ]]; then
    log "INFO" "Store may already exist; attempting to fetch existing store id."
    local store_get
    store_get=$(curl -sS -X GET "http://localhost:${MACH5_STORE_LOCAL_PORT}/apis/stores/${MACH5_STORE_NAME}")
    STORE_ID=$(printf '%s' "$store_get" | extract_store_id || true)
    if [[ -z "$STORE_ID" ]]; then
      echo "ERROR: Unable to extract store id from response." >&2
      echo "PUT response: $store_response" >&2
      echo "GET response: $store_get" >&2
      return 1
    fi
  fi
  log "INFO" "Store created with id '${STORE_ID}'."
}

store_route_exists() {
  if [[ "$DRY_RUN" == true ]]; then
    return 1
  fi

  local routes_response
  routes_response=$(curl -sS -X GET "http://localhost:${MACH5_STORE_LOCAL_PORT}/apis/store_routes")
  local compact
  compact=$(printf '%s' "$routes_response" | tr -d '\n' | tr -d '\r' | tr -d ' ')
  printf '%s' "$compact" | grep -q "\"store_id\":\"${STORE_ID}\""
}

create_store_route() {
  if store_route_exists; then
    log "INFO" "Store route already exists for store id '${STORE_ID}'."
    return 0
  fi

  log "INFO" "Creating store route for store id '${STORE_ID}'."
  if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "Dry run enabled; skipping store route creation."
    return 0
  fi

  local route_response
  route_response=$(curl -sS -X POST "http://localhost:${MACH5_STORE_LOCAL_PORT}/apis/store_routes" \
    -H "Content-Type: application/json" \
    -d "{
      \"pattern\": \"${MACH5_STORE_ROUTE_PATTERN}\",
      \"priority\": ${MACH5_STORE_ROUTE_PRIORITY},
      \"store_id\": \"${STORE_ID}\"
    }")

  log "INFO" "Store route created. Response: ${route_response}"
}

create_warehouse() {
  local warehouse_url
  warehouse_url="http://localhost:${MACH5_STORE_LOCAL_PORT}/apis/namespaces/default/warehouses/m5warehouse"
  log "INFO" "Calling: PUT ${warehouse_url}"
  if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "Dry run enabled; skipping warehouse creation."
    return 0
  fi

  local warehouse_response
  warehouse_response=$(curl -sS -X PUT "$warehouse_url" \
    -H "Content-Type: application/json" \
    -d '{
      "resource": {
        "os": null,
        "md": null,
        "ir": null,
        "osd": null,
        "mdx": null,
        "inactive_mode": null,
        "num_mediators": 1,
        "immutable": false,
        "osd_enabled": true,
        "segment_cache_capacity": null,
        "local_parallelism": null,
        "cache_warming_enabled": true,
        "cache_warming_query_history": null,
        "os_processors": null,
        "num_os": null,
        "num_replica": null,
        "index_access_memory_limit": null,
        "read_cache_size_limit": null
      },
      "enabled": true
    }')

  log "INFO" "Warehouse created. Response: ${warehouse_response}"
}

install_cert_manager() {
  log "INFO" "Installing cert-manager into the cluster."
  ensure_namespace cert-manager
  execute helm repo add jetstack https://charts.jetstack.io --force-update
  execute helm repo update
  execute helm upgrade --install cm jetstack/cert-manager --version v1.5.3 -n cert-manager -f "$VALUES_DIR/values_cm.yaml"
}

install_cache_proxy() {
  log "INFO" "Installing the cache-proxy chart."
  ensure_namespace cache-proxy
  helm_registry_login

  local cache_tgz="${MACH5_CACHE_PROXY_CHART}-${MACH5_CACHE_PROXY_VERSION}.tgz"
  execute rm -f "$cache_tgz"
  execute helm pull "${MACH5_ARTIFACT_REGISTRY}/${MACH5_CACHE_PROXY_CHART}" --version "$MACH5_CACHE_PROXY_VERSION"
  execute helm upgrade --install m5-cache "$cache_tgz" -n cache-proxy -f "$VALUES_DIR/values_cp.yaml"
}

install_mach5_search() {
  log "INFO" "Installing the Mach5 Search chart."
  ensure_namespace mach5
  helm_registry_login

  local search_tgz="${MACH5_SEARCH_CHART}-${MACH5_SEARCH_VERSION}.tgz"
  execute rm -f "$search_tgz"
  execute helm pull "${MACH5_ARTIFACT_REGISTRY}/${MACH5_SEARCH_CHART}" --version "$MACH5_SEARCH_VERSION"
  execute helm upgrade --install m5s "$search_tgz" -n mach5 -f "$VALUES_DIR/values_aks.yaml"
}

log "INFO" "Gathering AKS credentials for '$AKS_CLUSTER_NAME'."
execute az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing

install_cert_manager
install_cache_proxy
install_mach5_search

wait_for_mach5_pods
verify_mach5_pods_running
start_port_forward "mach5" "$MACH5_NGINX_SERVICE_NAME" "$MACH5_STORE_LOCAL_PORT" "$MACH5_NGINX_PORT"
create_store
create_store_route
create_warehouse

print_final_summary
