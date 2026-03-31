#!/usr/bin/env bash

configure_storage_access() {
  log "INFO" "Configuring access between AKS and the storage account."

  local storage_account_id
  storage_account_id=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query id -o tsv)

  local kubelet_identity_id
  kubelet_identity_id=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query identityProfile.kubeletidentity.objectId \
    -o tsv)

  local node_rg
  node_rg=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query nodeResourceGroup -o tsv)

  local vmss_name
  vmss_name=$(az vmss list \
    --resource-group "$node_rg" \
    --query "[?contains(name, '$MAIN_NODEPOOL_NAME')]|[0].name" \
    -o tsv)
  if [[ -z "$vmss_name" ]]; then
    log "WARN" "Unable to find a VMSS containing '$MAIN_NODEPOOL_NAME'; falling back to the first VMSS."
    vmss_name=$(az vmss list --resource-group "$node_rg" --query "[0].name" -o tsv)
  fi

  local aks_subnet_id
  aks_subnet_id=$(az vmss show \
    --resource-group "$node_rg" \
    --name "$vmss_name" \
    --query "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id" \
    -o tsv)

  if [[ -z "$aks_subnet_id" ]]; then
    printf "Unable to determine the AKS subnet ID.\n" >&2
    return 1
  fi

  if [[ -z "${CLUSTER_VNET_RESOURCE_GROUP:-}" ]]; then
    printf "CLUSTER_VNET_RESOURCE_GROUP is required to discover VNet details.\n" >&2
    return 1
  fi

  local discovered_vnet
  discovered_vnet=$(az network vnet list \
    --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
    --query "[].name | [0]" \
    -o tsv)

  if [[ -z "$discovered_vnet" ]]; then
    printf "Unable to determine VNet name in resource group '%s'.\n" "$CLUSTER_VNET_RESOURCE_GROUP" >&2
    return 1
  fi

  CLUSTER_VNET_NAME="$discovered_vnet"
  log "INFO" "Auto-detected VNet name: $CLUSTER_VNET_NAME"

  local discovered_subnet
  discovered_subnet=$(az network vnet subnet list \
    --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
    --vnet-name "$CLUSTER_VNET_NAME" \
    --query "[?networkSecurityGroup != null].name | [0]" \
    -o tsv)

  if [[ -z "$discovered_subnet" ]]; then
    printf "Unable to determine subnet name in VNet '%s' (resource group '%s').\n" \
      "$CLUSTER_VNET_NAME" "$CLUSTER_VNET_RESOURCE_GROUP" >&2
    return 1
  fi

  CLUSTER_SUBNET_NAME="$discovered_subnet"
  log "INFO" "Auto-detected subnet name: $CLUSTER_SUBNET_NAME"

  configure_subnet_service_endpoint
  configure_storage_network_rules "$aks_subnet_id"
  configure_storage_role_assignment "$kubelet_identity_id" "$storage_account_id"

  log "INFO" "Storage configuration completed for subnet '$aks_subnet_id'."
}

configure_subnet_service_endpoint() {
  local endpoints
  mapfile -t endpoints < <(az network vnet subnet show \
    --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
    --vnet-name "$CLUSTER_VNET_NAME" \
    --name "$CLUSTER_SUBNET_NAME" \
    --query "serviceEndpoints[].service" \
    -o tsv)

  local needs_update=true
  for endpoint in "${endpoints[@]}"; do
    if [[ "$endpoint" == "Microsoft.Storage" ]]; then
      needs_update=false
      break
    fi
  done

  if [[ "$needs_update" == true ]]; then
    endpoints+=("Microsoft.Storage")
    execute az network vnet subnet update \
      --resource-group "$CLUSTER_VNET_RESOURCE_GROUP" \
      --vnet-name "$CLUSTER_VNET_NAME" \
      --name "$CLUSTER_SUBNET_NAME" \
      --service-endpoints "${endpoints[@]}"
  else
    log "INFO" "Microsoft.Storage service endpoint already present on subnet."
  fi
}

configure_storage_network_rules() {
  local subnet_id=$1
  local existing
  existing=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "networkRuleSet.virtualNetworkRules[].id" \
    -o tsv)

  if ! printf '%s\n' "$existing" | grep -q -F "$subnet_id"; then
    execute az storage account network-rule add \
      --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
      --account-name "$STORAGE_ACCOUNT_NAME" \
      --subnet "$subnet_id"
  else
    log "INFO" "Subnet already allowed on the storage account."
  fi

  local default_action
  default_action=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "networkRuleSet.defaultAction" \
    -o tsv)
  if [[ "$default_action" != "Deny" ]]; then
    execute az storage account update \
      --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
      --name "$STORAGE_ACCOUNT_NAME" \
      --default-action Deny
  fi

  local current_tls
  current_tls=$(az storage account show \
    --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "minimumTlsVersion" \
    -o tsv)
  if [[ "$current_tls" != "TLS1_2" && "$current_tls" != "TLS1_3" ]]; then
    log "INFO" "Updating storage account TLS minimum from '$current_tls' to TLS1_2."
    execute az storage account update \
      --resource-group "$STORAGE_ACCOUNT_RESOURCE_GROUP" \
      --name "$STORAGE_ACCOUNT_NAME" \
      --min-tls-version TLS1_2
  else
    log "INFO" "Storage account already enforcing TLS >= $current_tls."
  fi
}

configure_storage_role_assignment() {
  local identity_id=$1
  local storage_account_id=$2

  local existing_role
  existing_role=$(az role assignment list \
    --assignee-object-id "$identity_id" \
    --scope "$storage_account_id" \
    --role "Storage Blob Data Contributor" \
    --query "[].id" \
    -o tsv)

  if [[ -z "$existing_role" ]]; then
    execute az role assignment create \
      --assignee-object-id "$identity_id" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "$storage_account_id"
  else
    log "INFO" "Storage Blob Data Contributor assignment already exists for the kubelet identity."
  fi
}
