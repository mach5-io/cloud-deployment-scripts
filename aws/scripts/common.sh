#!/bin/bash

tool_missing() {
    local tool=$1
    local message

    case "$tool" in
        yq)
            message="Go-based yq v4+ from https://github.com/mikefarah/yq"
            ;;
        kubectl)
            message="kubectl v1.31+ version"
            ;;
        terraform)
            message="terraform v1.12.1+"
            ;;
        aws)
            message="aws cli 2.25.8+"
            ;;
        eksctl)
            message="eksctl 0.207.0+"
            ;;
        curl)
            message="curl 8.5+"
            ;;
        *)
            message="required tool"
            ;;
    esac

    echo "$tool not found or version not supported, please install $message"
    exit 1
}

check_tool() {
    which "$1" >/dev/null || tool_missing "$1"
}

check_version() {
    local tool=$1
    local version_cmd="$2"
    local required_major=$3
    local required_minor=$4

    local version
    version=$($version_cmd 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)

    if [[ -z "$version" ]]; then
        echo "Could not determine version of $tool"
        tool_missing "$tool"
    fi

    local major=${version%%.*}
    local minor=${version#*.}

    if [[ "$major" -lt "$required_major" ]]; then
        tool_missing "$tool"
    elif [[ -n "$required_minor" && "$major" -eq "$required_major" && "$minor" -lt "$required_minor" ]]; then
        tool_missing "$tool"
    fi

    echo "$tool version: $version"
}

initialize_env() { 
    # Check if required tools are installed
    check_tool yq
    check_tool kubectl
    check_tool aws
    check_tool curl

    # Check versions
    check_version yq "yq --version" 4        
    check_version kubectl "kubectl version" 1 31        
    check_version aws "aws --version" 2 9
    check_version curl "curl --version" 7 81

    setup_folders $1
}

update_eksctl_config() {
    EKSCTL_BASE=$M5_CLUSTER_BASE_DIR/eksctl
    # Ensure randomized password is set for metadatadb password 
    PASS_VALUE=$(yq eval '.metadatadb.password // ""' $EKSCTL_BASE/values.yaml)

    if [ -z "$PASS_VALUE" ]; then
      export PASSWD=$(yq eval '.mach5-config.db-password' $M5_CONFIG_FILE)
      yq -i '.metadatadb.password = strenv(PASSWD)' $EKSCTL_BASE/values.yaml
    fi

    export service_account=$(yq eval '.cluster-config.service_account_name' $M5_CONFIG_FILE)
    yq -i '.serviceAccount.name = strenv(service_account)' $EKSCTL_BASE/values.yaml

    export cluster_name=$(yq eval '.cluster-config.name' $M5_CONFIG_FILE)
    yq -i '.metadata.name = strenv(cluster_name)' $EKSCTL_BASE/cluster.yaml

    export region=$(yq eval '.cluster-config.region' $M5_CONFIG_FILE)
    yq -i '.metadata.region = strenv(region)' $EKSCTL_BASE/cluster.yaml

}

update_terraform_config() {
    # Ensure randomized password is set for metadatadb password 
    TERRAFORM_BASE=$M5_CLUSTER_BASE_DIR/terraform
    PASS_VALUE=$(yq eval '.metadatadb.password // ""' $TERRAFORM_BASE/values.yaml)

    if [ -z "$PASS_VALUE" ]; then
      export PASSWD=$(yq eval '.mach5-config.db-password' $M5_CONFIG_FILE)
      yq -i '.metadatadb.password = strenv(PASSWD)' $TERRAFORM_BASE/values.yaml
    fi

    export service_account=$(yq eval '.cluster-config.service_account_name' $M5_CONFIG_FILE)
    yq -i '.serviceAccount.name = strenv(service_account)' $TERRAFORM_BASE/values.yaml

    export warehouse_head_resource=$(yq eval '.cluster-config.node-groups.warehouse-head.instance-type' $M5_CONFIG_FILE) 
    yq eval ".mediatorwarehousecontroller.headresource = \"aws.$warehouse_head_resource\"" -i $TERRAFORM_BASE/values.yaml
    export warehouse_worker_resource=$(yq eval '.cluster-config.node-groups.warehouse-worker.instance-type' $M5_CONFIG_FILE) 
    yq eval ".mediatorwarehousecontroller.workerresource = \"aws.$warehouse_worker_resource\"" -i $TERRAFORM_BASE/values.yaml
    # Ensure tfvars is set for all values in config file.
    generate_tfvars
    
}

setup_folders() {

    M5_BASE_CONFIG_FILE="$M5_BASE_DIR/config.yaml"

    export CLUSTER_NAME=$(yq '.cluster-config.name' $M5_BASE_CONFIG_FILE)
    if [ -z "$CLUSTER_NAME" ]; then
        echo "❌ Error: .cluster-config.name is empty or not set in config.yaml"
        exit 1
    fi

    export MACH5_VERSION=$(yq '.mach5-config.version' $M5_BASE_CONFIG_FILE)
    if [ -z "$MACH5_VERSION" ]; then
        echo "❌ Error: .mach5-config.version is empty or not set in config.yaml"
        exit 1
    fi

    export M5_CLUSTER_BASE_DIR="$M5_BASE_DIR/_$CLUSTER_NAME"

    export M5_CONFIG_FILE=$M5_CLUSTER_BASE_DIR/config.yaml

    if [ -f "$M5_CONFIG_FILE" ]; then
        echo "Using existing config file $M5_CONFIG_FILE"
    else
        prepare_configfile
        if [ ! -d "$M5_CLUSTER_BASE_DIR" ]; then
            echo "creating $M5_CLUSTER_BASE_DIR..."
            mkdir -p $M5_CLUSTER_BASE_DIR
        fi
        mv $M5_TEMP_CONFIG_FILE  $M5_CLUSTER_BASE_DIR/config.yaml 

        local mode="$1"  
        if [ "$mode" = "single" ]; then
            cp -R $M5_BASE_DIR/eksctl $M5_CLUSTER_BASE_DIR/
        else
            cp -R $M5_BASE_DIR/terraform $M5_CLUSTER_BASE_DIR/
        fi
    fi

    export HELM_RELEASE_NAME=$(yq '.mach5-config.release-name' $M5_CONFIG_FILE)
    export REGION=$(yq '.cluster-config.region' $M5_CONFIG_FILE)
    export NAMESPACE=$(yq '.mach5-config.namespace' $M5_CONFIG_FILE)
    export SERVICE_ACCOUNT_NAME=$(yq '.cluster-config.service_account_name' $M5_CONFIG_FILE)
    export S3_BUCKET=$(yq '.cluster-config.s3-bucket' $M5_CONFIG_FILE)

}


prepare_configfile() {

    cp $M5_BASE_CONFIG_FILE $M5_BASE_DIR/.m5.config.yaml
    export M5_TEMP_CONFIG_FILE=$M5_BASE_DIR/.m5.config.yaml

    s3_postfix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)
    s3_bucket_temp=$(yq '.cluster-config.s3-bucket' $M5_TEMP_CONFIG_FILE)
    export S3_BUCKET="$s3_bucket_temp-$s3_postfix"
    yq eval ".cluster-config.s3-bucket = \"$S3_BUCKET\"" -i "$M5_TEMP_CONFIG_FILE"

    password=$(yq eval '.mach5-config.db-password // ""' $M5_TEMP_CONFIG_FILE)

    if [ -z "$password" ]; then
        temp_db_password=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)
        yq eval ".mach5-config.db-password = \"$temp_db_password\"" -i "$M5_TEMP_CONFIG_FILE"
    fi
}

yaml_paths=(
  "mach5-config.namespace"
  "mach5-config.version"
  "mach5-config.release-name"
  "cluster-config.name"
  "cluster-config.region"
  "cluster-config.s3-bucket"
  "cluster-config.prefix"
  "cluster-config.vpc.cidr-block"
  "cluster-config.vpc.cluster-service-cidr"
  "cluster-config.vpc.route-table.public"
  "cluster-config.vpc.route-table.private"
  "cluster-config.vpc.subnet.private.cidr1"
  "cluster-config.vpc.subnet.private.zone1"
  "cluster-config.vpc.subnet.private.cidr2"
  "cluster-config.vpc.subnet.private.zone2"
  "cluster-config.vpc.subnet.public.cidr1"
  "cluster-config.vpc.subnet.public.zone1"
  "cluster-config.vpc.subnet.public.cidr2"
  "cluster-config.vpc.subnet.public.zone2"
  "cluster-config.service_account_name"
  "cluster-config.ebs.addon-version"
  "cluster-config.ebs.storageclass.name"
  "cluster-config.ebs.storageclass.provisioner"
  "cluster-config.node-groups.warehouse-head.instance-type"
  "cluster-config.node-groups.warehouse-head.capacity"
  "cluster-config.node-groups.warehouse-head.desired-size"
  "cluster-config.node-groups.warehouse-head.min-size"
  "cluster-config.node-groups.warehouse-head.max-size"
  "cluster-config.node-groups.warehouse-worker.instance-type"
  "cluster-config.node-groups.warehouse-worker.ami-type"
  "cluster-config.node-groups.warehouse-worker.capacity"
  "cluster-config.node-groups.warehouse-worker.desired-size"
  "cluster-config.node-groups.warehouse-worker.min-size"
  "cluster-config.node-groups.warehouse-worker.max-size"
  "cluster-config.node-groups.ingestor.instance-type"
  "cluster-config.node-groups.ingestor.ami-type"
  "cluster-config.node-groups.ingestor.capacity"
  "cluster-config.node-groups.ingestor.desired-size"
  "cluster-config.node-groups.ingestor.min-size"
  "cluster-config.node-groups.ingestor.max-size"
  "cluster-config.node-groups.compactor.instance-type"
  "cluster-config.node-groups.compactor.ami-type"
  "cluster-config.node-groups.compactor.capacity"
  "cluster-config.node-groups.compactor.desired-size"
  "cluster-config.node-groups.compactor.min-size"
  "cluster-config.node-groups.compactor.max-size"
  "cluster-config.node-groups.main.instance-type"
  "cluster-config.node-groups.main.capacity"
  "cluster-config.node-groups.main.desired-size"
  "cluster-config.node-groups.main.min-size"
  "cluster-config.node-groups.main.max-size"
  "cluster-config.node-groups.ccs.instance-type"
  "cluster-config.node-groups.ccs.capacity"
  "cluster-config.node-groups.ccs.desired-size"
  "cluster-config.node-groups.ccs.min-size"
  "cluster-config.node-groups.ccs.max-size"
  "cluster-config.node-groups.settings.log-max-size"
  "cluster-config.node-groups.settings.log-max-files"
)

tfvar_names=(
  "namespace"
  "mach5_helm_chart_version"
  "mach5_helm_release_name"
  "cluster_name"
  "aws_region"
  "mach5_s3_bucket_name"
  "prefix"
  "vpc_cidr_block"
  "cluster_service_cidr"
  "public_route_table"
  "private_route_table"
  "private-subnet-cidr-1"
  "private-subnet-zone-1"
  "private-subnet-cidr-2"
  "private-subnet-zone-2"
  "public-subnet-cidr-1"
  "public-subnet-zone-1"
  "public-subnet-cidr-2"
  "public-subnet-zone-2"
  "service_account_name"
  "ebs_addon_version"
  "storageclass_name"
  "storageclass_provisioner"
  "warehouse_head_node_instance_type"
  "warehouse_head_node_capacity_type"
  "warehouse_head_node_desired_size"
  "warehouse_head_node_min_size"
  "warehouse_head_node_max_size"
  "warehouse_node_instance_type"
  "warehouse_ami_type"
  "warehouse_node_capacity_type"
  "warehouse_node_desired_size"
  "warehouse_node_min_size"
  "warehouse_node_max_size"
  "ingestor_node_instance_type"
  "ingestor_ami_type"
  "ingestor_node_capacity_type"
  "ingestor_node_desired_size"
  "ingestor_node_min_size"
  "ingestor_node_max_size"
  "compactor_node_instance_type"
  "compactor_ami_type"
  "compactor_node_capacity_type"
  "compactor_node_desired_size"
  "compactor_node_min_size"
  "compactor_node_max_size"
  "cluster_node_instance_type"
  "cluster_node_capacity_type"
  "cluster_node_desired_size"
  "cluster_node_min_size"
  "cluster_node_max_size"
  "ccs_node_instance_type"
  "ccs_node_capacity_type"
  "ccs_node_desired_size"
  "ccs_node_min_size"
  "ccs_node_max_size"
  "log_max_size"
  "log_max_files"
)

list_string_vars=(
  "warehouse_head_node_instance_type"
  "warehouse_node_instance_type"
  "ingestor_node_instance_type"
  "compactor_node_instance_type"
  "cluster_node_instance_type"
  "ccs_node_instance_type"
)

is_list_string_var() {
  local var="$1"
  for item in "${list_string_vars[@]}"; do
    if [[ "$item" == "$var" ]]; then
      return 0
    fi
  done
  return 1
}

generate_tfvars() {

    export TFVARS_FILE=$M5_CLUSTER_BASE_DIR/terraform/mach5.tfvars
    if [ -f "$TFVARS_FILE" ]; then
          rm $TFVARS_FILE
    fi
    touch $TFVARS_FILE
    for i in "${!yaml_paths[@]}"; do
        yaml_path="${yaml_paths[$i]}"
        tfvar_key="${tfvar_names[$i]}"
        value=$(yq e ".$yaml_path" "$M5_CONFIG_FILE")

        if [[ "$value" == "null" || -z "$value" ]]; then
            echo "❌ Error: Missing or empty value at YAML path '$yaml_path'"
            exit 1
        fi

        if is_list_string_var "$tfvar_key"; then
            echo "$tfvar_key = [\"$value\"]" >> "$TFVARS_FILE"
        elif [[ "$value" =~ ^[0-9]+$ || "$value" =~ ^true$|^false$ ]]; then
            echo "$tfvar_key = $value" >> "$TFVARS_FILE"
        else
            echo "$tfvar_key = \"$value\"" >> "$TFVARS_FILE"
        fi
    done
    

}
# updating currnt shell's kube config to point to EKS cluster
update_kubeconfig() {
    KUBECONFIG_FILE="$M5_CLUSTER_BASE_DIR/kubeconfig"
    aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_FILE"
    export KUBECONFIG=$KUBECONFIG_FILE
}

# waiting for nginx pod to come up.

wait_until() {
    local cmd="$1"
    local timeout=${2:-60}
    local interval=${3:-5}
    local elapsed=0

    while true; do
      if eval "$cmd"; then
        return 0
      fi

      if (( elapsed >= timeout )); then
        echo $cmd
        echo "❌ Timeout: Command did not succeed within $timeout seconds."
        return 1
      fi

      echo "Waiting... (elapsed ${elapsed}s)"
      sleep "$interval"
      elapsed=$((elapsed + interval))
    done  
}

ensure_mach5_up_running() {
    POD_NAME=nginx

    wait_until '[[ "$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "$POD_NAME" | awk "{print \$3}")" == "Running" ]]' 120 10
    if [[ $? -ne 0 ]]; then
      echo "Pod '$POD_NAME' did not reach Running state in time."
      exit 1
    fi

    LISTEN_PORT=8888

    if netstat -tln 2>/dev/null | grep -q ":$LISTEN_PORT "; then
        echo "Looks like port forward already setup on $LISTEN_PORT..."
    else
        nohup kubectl -n $NAMESPACE port-forward svc/$HELM_RELEASE_NAME-nginx $LISTEN_PORT:80 > /tmp/mach5-port-forward.log &
    fi

    wait_until '[[ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$LISTEN_PORT/apis/stores")" == "200" ]]' 30 5
    if [[ $? -ne 0 ]]; then
      echo "Deployment failed or timed out"
      exit 1
    fi
}

create_mach5_config() {
    STORE_ID=`curl -sS -X PUT "http://localhost:$LISTEN_PORT/apis/stores/s3_store"  -H 'content-type: application/json' -d '{"bucket":"'$S3_BUCKET'", "prefix":"store","type":"s3"}' | jq .id`
    echo created store s3_store with id=$STORE_ID
    echo adding store route
    sleep 2
    curl -sS -o /dev/null -X POST "http://localhost:$LISTEN_PORT/apis/store_routes" -H 'content-type: application/json' -d '{"pattern":".*","priority":10,"store_id":'$STORE_ID'}' 

    echo createing warehouse with name \'getting-started\'
    sleep 2
    curl -sS -o /dev/null -X PUT "http://localhost:$LISTEN_PORT/apis/namespaces/default/warehouses/getting-started" \
    -H 'accept: application/json'\
    -H 'content-type: application/json' \
    -d '{"resource":{"immutable":false,"num_mediators":1,"osd_enabled":true, "cache_warming_enabled": true}}' 

    echo '---------------------'
    echo getting started resources created
    echo NOTE: The warehouse can take upto one minute to be ready. 
    echo '      'After a minute you can access using the following urls
    echo '---------------------'
}

final_setup() {
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$LISTEN_PORT/apis/namespaces/default/warehouses/getting-started")
    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "Mach5 config setup already done"
    else
        create_mach5_config
    fi

    echo To connect to EKS cluster use following command from shell:
    echo export KUBECONFIG=$KUBECONFIG_FILE 
    echo  
    echo If port-forwarding breaks for some reason, run following:
    echo kubectl -n $NAMESPACE port-forward svc/$HELM_RELEASE_NAME-nginx $LISTEN_PORT:80 
    echo 
    echo Access Dashboards at the following url:
    echo ' 'http://localhost:$LISTEN_PORT/warehouse/default/getting-started/dashboards/
    echo
    echo Access Opensearch api at the following url:
    echo ' 'http://localhost:$LISTEN_PORT/warehouse/default/getting-started/opensearch/

}

