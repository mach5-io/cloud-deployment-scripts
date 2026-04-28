#!/usr/bin/env bash

ensure_node_pools() {
  if [[ ${#NODEPOOLS[@]} -eq 0 ]]; then
    log "WARN" "NODEPOOLS is empty; no additional node pools will be managed."
    return 0
  fi

  for entry in "${NODEPOOLS[@]}"; do
    IFS='|' read -r pool_name pool_vm_size pool_min pool_max pool_count pool_labels pool_nvme pool_osdisk_size_gb <<< "$entry"
    log "INFO" "Ensuring node pool '$pool_name' exists with SKU '$pool_vm_size'."

    local update_args=(
      az aks nodepool update
      --resource-group "$RESOURCE_GROUP"
      --cluster-name "$AKS_CLUSTER_NAME"
      --name "$pool_name"
      --min-count "$pool_min"
      --max-count "$pool_max"
      --labels "$pool_labels"
      --update-cluster-autoscaler
    )

    local pool_exists=true
    if ! az aks nodepool show --resource-group "$RESOURCE_GROUP" --cluster-name "$AKS_CLUSTER_NAME" --name "$pool_name" > /dev/null 2>&1; then
      pool_exists=false
    fi

    if [[ "$pool_exists" == true ]]; then
      log "INFO" "Node pool '$pool_name' already exists; updating autoscaler and labels."
      execute "${update_args[@]}"
    else
      log "INFO" "Creating node pool '$pool_name'."
      update_args=(
        az aks nodepool add
        --resource-group "$RESOURCE_GROUP"
        --cluster-name "$AKS_CLUSTER_NAME"
        --name "$pool_name"
        --node-vm-size "$pool_vm_size"
        --labels "$pool_labels"
        --enable-cluster-autoscaler
        --min-count "$pool_min"
        --max-count "$pool_max"
        --node-count "$pool_count"
      )

      local disk_type="Managed"
      if [[ "$pool_nvme" == "true" ]]; then
        disk_type="Ephemeral"
      fi
      update_args+=(--node-osdisk-type "$disk_type")
      if [[ -n "$pool_osdisk_size_gb" ]]; then
        update_args+=(--node-osdisk-size "$pool_osdisk_size_gb")
      fi

      execute "${update_args[@]}"
    fi
  done
}
