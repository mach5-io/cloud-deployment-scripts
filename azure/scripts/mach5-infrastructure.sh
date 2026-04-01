#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/create-cluster.sh"
source "$SCRIPT_DIR/nodepools.sh"
source "$SCRIPT_DIR/storage-access.sh"

CONFIG_OVERRIDE=""
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

usage() {
  cat <<EOF
Usage: $0 [-v|--verbose] [--dry-run] [--config PATH]

Options:
  -v, --verbose    Enable trace logging for each command.
  --dry-run        Do not execute commands; print them only (implies verbose).
  --config PATH    Load configuration from PATH instead of the shared default.
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
        echo "Missing argument for --config" >&2
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

log "INFO" "Starting Mach5 deployment (cluster=$AKS_CLUSTER_NAME, resource group=$RESOURCE_GROUP)."
create_cluster
ensure_node_pools
log "INFO" "Fetching AKS credentials for kubectl."
execute az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing
log "INFO" "Fetching kube-system namespace UID for license generation."
if [[ "$DRY_RUN" == true ]]; then
  log "INFO" "Dry run enabled; skipping kubectl UID fetch."
else
  VALUES_AKS_PATH="$SCRIPT_DIR/../values/values_aks.yaml"
  license_token=$(awk '
    /^[[:space:]]*license:[[:space:]]*$/ {in_license=1; next}
    in_license && /^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*/ {
      key=$1; sub(":", "", key);
      if (key=="token") {
        val=$0;
        sub(/^[^:]*:[[:space:]]*/, "", val);
        gsub(/["'\''[:space:]]/, "", val);
        print val;
        exit
      }
    }
  ' "$VALUES_AKS_PATH")

  if [[ -z "$license_token" || "$license_token" == "CHANGE_ME" ]]; then
    kube_system_uid=$(kubectl get ns kube-system -o jsonpath='{.metadata.uid}')
    printf "\nKUBE_SYSTEM_UID=%s\n\n" "$kube_system_uid"
    log "INFO" "Send the KUBE_SYSTEM_UID value to the Mach5 administrator to generate a license."
    log "INFO" "Once received, update license.token in values/values_aks.yaml and rerun this script."
    exit 10
  else
    log "INFO" "License token detected in values/values_aks.yaml; continuing deployment."
  fi
fi
configure_storage_access
log "INFO" "Mach5 deployment steps completed successfully."
