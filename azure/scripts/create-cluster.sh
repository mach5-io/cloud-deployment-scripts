#!/usr/bin/env bash

create_cluster() {
  log "INFO" "Ensuring AKS cluster '$AKS_CLUSTER_NAME' exists in '$RESOURCE_GROUP'."
  if az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" > /dev/null 2>&1; then
    log "INFO" "AKS cluster '$AKS_CLUSTER_NAME' already exists."
    return 0
  fi

  local args=(
    az aks create
    --resource-group "$RESOURCE_GROUP"
    --name "$AKS_CLUSTER_NAME"
    --location "$LOCATION"
    --kubernetes-version "$KUBERNETES_VERSION"
    --network-plugin azure
    --enable-managed-identity
    --enable-workload-identity
    --enable-oidc-issuer
    --nodepool-name "$MAIN_NODEPOOL_NAME"
    --node-vm-size "$MAIN_NODEPOOL_VM_SIZE"
    --nodepool-labels "$MAIN_NODEPOOL_LABELS"
    --enable-cluster-autoscaler
    --min-count "$MAIN_NODEPOOL_MIN"
    --max-count "$MAIN_NODEPOOL_MAX"
    --node-count "$MAIN_NODEPOOL_NODE_COUNT"
    --service-cidr "$SERVICE_CIDR"
    --dns-service-ip "$DNS_SERVICE_IP"
    --generate-ssh-keys
  )

  if [[ -n "${CLUSTER_SUBNET_ID:-}" ]]; then
    args+=(--vnet-subnet-id "$CLUSTER_SUBNET_ID")
  fi

  execute "${args[@]}"
}
