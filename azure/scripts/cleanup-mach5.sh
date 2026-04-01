#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"

CONFIG_OVERRIDE=""
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

usage() {
  cat <<EOF
Usage: $0 [-v|--verbose] [--dry-run] [--config PATH]

Options:
  -v, --verbose    Print each command before running it.
  --dry-run        Skip actual execution (implies verbose output).
  --config PATH    Use a custom configuration file.
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

CLUSTER_SUBNET_ID=${CLUSTER_SUBNET_ID:-""}
CLUSTER_VNET_RESOURCE_GROUP=${CLUSTER_VNET_RESOURCE_GROUP:-""}
CLUSTER_VNET_NAME=${CLUSTER_VNET_NAME:-""}
CLUSTER_SUBNET_NAME=${CLUSTER_SUBNET_NAME:-""}

if [[ "$VERBOSE" == true ]]; then
  set -x
fi

log "INFO" "Starting Mach5 cleanup (cluster=$AKS_CLUSTER_NAME, resource group=$RESOURCE_GROUP)."

cluster_exists=false
kubelet_identity_id=""
node_rg=""
main_vmss_name=""

if az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" > /dev/null 2>&1; then
  cluster_exists=true
  kubelet_identity_id=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query identityProfile.kubeletidentity.objectId -o tsv)
  node_rg=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query nodeResourceGroup -o tsv)
else
  log "WARN" "AKS cluster '$AKS_CLUSTER_NAME' not found; skipping cluster-specific cleanup."
fi

AKS_SUBNET_ID_RESOLVED="$CLUSTER_SUBNET_ID"
if [[ -z "$AKS_SUBNET_ID_RESOLVED" && "$cluster_exists" == true && -n "$node_rg" ]]; then
  main_vmss_name=$(az vmss list \
    --resource-group "$node_rg" \
    --query "[?contains(name, '$MAIN_NODEPOOL_NAME')]|[0].name" \
    -o tsv)
  if [[ -z "$main_vmss_name" ]]; then
    log "WARN" "Main node pool VMSS not found; defaulting to first VMSS."
    main_vmss_name=$(az vmss list \
      --resource-group "$node_rg" \
      --query "[0].name" \
      -o tsv)
  fi

  if [[ -n "$main_vmss_name" ]]; then
    AKS_SUBNET_ID_RESOLVED=$(az vmss show \
      --resource-group "$node_rg" \
      --name "$main_vmss_name" \
      --query "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id" \
      -o tsv)
  fi
fi

if [[ -n "$AKS_SUBNET_ID_RESOLVED" ]]; then
  if [[ -z "$CLUSTER_VNET_RESOURCE_GROUP" ]]; then
    CLUSTER_VNET_RESOURCE_GROUP=$(printf '%s' "$AKS_SUBNET_ID_RESOLVED" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="resourceGroups"){print $(i+1); break}}')
  fi
  if [[ -z "$CLUSTER_VNET_NAME" ]]; then
    CLUSTER_VNET_NAME=$(printf '%s' "$AKS_SUBNET_ID_RESOLVED" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="virtualNetworks"){print $(i+1); break}}')
  fi
  if [[ -z "$CLUSTER_SUBNET_NAME" ]]; then
    CLUSTER_SUBNET_NAME=$(printf '%s' "$AKS_SUBNET_ID_RESOLVED" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="subnets"){print $(i+1); break}}')
  fi
fi

remove_service_endpoint() {
  if [[ -z "$CLUSTER_VNET_RESOURCE_GROUP" || -z "$CLUSTER_VNET_NAME" || -z "$CLUSTER_SUBNET_NAME" ]]; then
    log "WARN" "Skipping subnet service endpoint cleanup; VNet/subnet identifiers are not available."
    return 0
  fi
  local endpoints
  mapfile -t endpoints < <(az network vnet subnet show \
    --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
    --vnet-name "$CLUSTER_VNET_NAME" \
    --name "$CLUSTER_SUBNET_NAME" \
    --query "serviceEndpoints[].service" \
    -o tsv)

  local filtered=()
  local saw_storage=false
  for endpoint in "${endpoints[@]}"; do
    if [[ "$endpoint" == "Microsoft.Storage" ]]; then
      saw_storage=true
      continue
    fi
    filtered+=("$endpoint")
  done

  if [[ "$saw_storage" != true ]]; then
    log "INFO" "Microsoft.Storage service endpoint already absent from subnet."
    return 0
  fi

  if [[ ${#filtered[@]} -gt 0 ]]; then
    execute az network vnet subnet update \
      --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
      --vnet-name "$CLUSTER_VNET_NAME" \
      --name "$CLUSTER_SUBNET_NAME" \
      --service-endpoints "${filtered[@]}"
  else
    execute az network vnet subnet update \
      --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
      --vnet-name "$CLUSTER_VNET_NAME" \
      --name "$CLUSTER_SUBNET_NAME" \
      --set serviceEndpoints=[]
  fi
}

remove_storage_network_rule() {
  if [[ -z "$AKS_SUBNET_ID_RESOLVED" ]]; then
    log "WARN" "AKS subnet ID unavailable; skipping storage network rule cleanup."
    return 0
  fi

  local existing
  existing=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "networkRuleSet.virtualNetworkRules[].id" \
    -o tsv)

  if printf '%s\n' "$existing" | grep -q -F "$AKS_SUBNET_ID_RESOLVED"; then
    execute az storage account network-rule remove \
      --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
      --account-name "$STORAGE_ACCOUNT_NAME" \
      --subnet "$AKS_SUBNET_ID_RESOLVED"
  else
    log "INFO" "Subnet not present in storage account network rules."
  fi

  local default_action
  default_action=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "networkRuleSet.defaultAction" \
    -o tsv)
  if [[ "$default_action" != "Allow" ]]; then
    execute az storage account update \
      --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
      --name "$STORAGE_ACCOUNT_NAME" \
      --default-action Allow
  fi
}

remove_storage_role_assignments() {
  if [[ -z "$kubelet_identity_id" ]]; then
    log "WARN" "Kubelet identity not available; skipping role assignment cleanup."
    return 0
  fi

  local subscription_id
  subscription_id=$(az account show --query id -o tsv)
  local storage_scope="/subscriptions/$subscription_id/resourceGroups/$STORAGE_ACCOUNT_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"

  local assignments
  assignments=$(az role assignment list \
    --assignee-object-id "$kubelet_identity_id" \
    --scope "$storage_scope" \
    --role "Storage Blob Data Contributor" \
    --query "[].id" \
    -o tsv)

  if [[ -z "$assignments" ]]; then
    log "INFO" "No Storage Blob Data Contributor assignment found for the kubelet identity."
    return 0
  fi

  while IFS= read -r assignment_id; do
    if [[ -n "$assignment_id" ]]; then
      execute az role assignment delete --ids "$assignment_id"
    fi
  done <<< "$assignments"
}

cleanup_storage_access() {
  log "INFO" "Removing storage access configuration."
  remove_service_endpoint
  remove_storage_network_rule
  remove_storage_role_assignments
}

delete_cluster() {
  if [[ "$cluster_exists" != true ]]; then
    log "INFO" "No AKS cluster to delete."
    return 0
  fi

  execute az aks delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --yes \
    --no-wait
  log "INFO" "Deletion initiated for AKS cluster '$AKS_CLUSTER_NAME'."
}

set +e
cleanup_storage_access
cleanup_status=$?
set -e

if [[ $cleanup_status -ne 0 ]]; then
  log "WARN" "Storage cleanup step failed (exit $cleanup_status); continuing with cluster deletion."
fi

delete_cluster

log "INFO" "Mach5 cleanup complete."
