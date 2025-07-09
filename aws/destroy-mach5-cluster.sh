#!/bin/bash

M5_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
cluster_name=$(yq '.cluster-config.name' $M5_BASE_DIR/config.yaml)

region=$(yq '.cluster-config.region' $M5_BASE_DIR/_$cluster_name/config.yaml)

M5_CLUSTER_TERRAFORM_BASE_DIR="$M5_BASE_DIR/_$cluster_name/terraform"

if [ -d "$M5_CLUSTER_TERRAFORM_BASE_DIR" ]; then
    cd $M5_CLUSTER_TERRAFORM_BASE_DIR
    terraform destroy -var-file="mach5.tfvars" -auto-approve
else 
    eksctl delete cluster  $cluster_name --region $region
fi 
