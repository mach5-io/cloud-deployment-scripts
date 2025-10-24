#!/bin/bash

source $M5_BASE_DIR/scripts/common.sh

check_tool eksctl
check_version eksctl "eksctl version" 0 207

initialize_env "eksctl"

update_eksctl_config 

EKSCTL_FLAG_FILE="$M5_CLUSTER_BASE_DIR/mach5.eksctl_applied"

if [ -f "$EKSCTL_FLAG_FILE" ]; then
    echo "EKS cluster already created with eksctl. Skipping."
else
    echo "Creating EKS cluster using eksctl..."

    eksctl create cluster -f $M5_CLUSTER_BASE_DIR/eksctl/cluster.yaml

    if [ $? -ne 0 ]; then
        echo "❌ eksctl cluster creation failed."
        exit 1
    fi

    eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --region $REGION

    eksctl create iamserviceaccount  --region "$REGION" --cluster $CLUSTER_NAME  --name $SERVICE_ACCOUNT_NAME  --namespace $NAMESPACE  --attach-policy-arn arn:aws:iam::aws:policy/AWSMarketplaceMeteringFullAccess  --attach-policy-arn arn:aws:iam::aws:policy/AWSMarketplaceMeteringRegisterUsage  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --approve

    touch "$EKSCTL_FLAG_FILE"
fi

update_kubeconfig

export HELM_EXPERIMENTAL_OCI=1
aws ecr get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin 709825985650.dkr.ecr.us-east-1.amazonaws.com

helm pull oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/mach5-software/mach5-io --version $MACH5_VERSION

helm upgrade --install -n $NAMESPACE  --create-namespace $HELM_RELEASE_NAME mach5-io-$MACH5_VERSION.tgz -f $M5_CLUSTER_BASE_DIR/eksctl/values.yaml 

rm mach5-io-$MACH5_VERSION.tgz

S3_EXISTS=$(aws s3api head-bucket --bucket "$S3_BUCKET" 2>&1 || true)

if echo "$S3_EXISTS" | grep -q 'Not Found'; then
    echo "Creating S3 bucket: $S3_BUCKET in region $REGION"
    aws s3api create-bucket --bucket "$S3_BUCKET" --create-bucket-configuration LocationConstraint="$REGION"  
    if [ $? -ne 0 ]; then
        echo "❌ eksctl cluster creation failed."
        exit 1
    fi
elif echo "$S3_EXISTS" | grep -q 'Forbidden'; then
    echo "❌ Bucket $S3_BUCKET already exists but not accessible."
    exit 1
else
    echo "✅ S3 bucket $S3_BUCKET already exists or accessible."
fi

ensure_mach5_up_running

final_setup

