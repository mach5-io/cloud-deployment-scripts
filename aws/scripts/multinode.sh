#!/bin/bash

source $M5_BASE_DIR/scripts/common.sh

check_tool terraform
check_version terraform "terraform version" 1 12

initialize_env "multinode"

update_terraform_config 

# Invoke terraform init, apply to create EKS cluster and helm chart installation

TR_FLAG_FILE="$M5_CLUSTER_BASE_DIR/mach5.tf_applied"

terraform_install() {
    echo "Initializing Terraform...to setup EKS cluster"
    sleep 5
    cd $M5_CLUSTER_BASE_DIR/terraform
    terraform init

    echo "Running terraform apply..."
    sleep 5

    terraform apply -var-file="mach5.tfvars" -auto-approve 

    if [ $? -ne 0 ]; then
        echo "❌ Terraform apply failed. Exiting."
        exit 1
    fi
    cd $M5_BASE_DIR
}

if [ -f "$TR_FLAG_FILE" ]; then
    echo "Terraform setup previously completed. Skipping."
else
    terraform_install
    touch "$TR_FLAG_FILE"
fi

update_kubeconfig

ensure_mach5_up_running

final_setup