variable "use_ecr" {
 type = bool
 default = true
 description = "Enable Mach5 deployment from Aamzon ECR "
}

variable "aws_region" {
  type = string
  default = "us-east-1"
  description = "AWS region for resources"
}

variable "artifact_registry_password" {
 type = string
 default = "CHANGE_ME"
 description = "Base64 encoded password key to access Mach5 Artifact registry"
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use. Leave empty to create a new VPC."
  type        = string
  default     = ""
}

variable "igw_id" {
  description = "ID of existing Internet gateway in the existing VPC."
  type        = string
  default     = "CHANGE_ME" # set if using existing_vpc_id
}

variable "mach5_helm_chart_version" {
 type = string
 default = "4.7.0-snapshot-30253cb"
 description = "Specify the exact helm chart version to install"
}

variable "enable_cluster_autoscaling" {
  type        = bool
  description = "Enable cluster autoscaling in the EKS cluster"
  default     = true
}

variable "artifact_registry_email" {
 type = string
 default = "CHANGE_ME"
 description = "GCP service account email to access Mach5 Artifact registry"
}

variable "mach5_s3_bucket_name" {
 type = string
 default = "mach5-search-bucket"
 description = "S3 bucket for being used as Mach5 Search store"
}

variable "warehouse_ami_type" {
  type = string
  description = "Type of Amazon Machine Image (AMI) associated with the Warehouse worker Node Group. Default=AL2_x86_64. For ARM AMIs, use AL2_ARM_64"
  default = "AL2_x86_64"
}

variable "ingestor_ami_type" {
  type = string
  description = "Type of Amazon Machine Image (AMI) associated with the Ingestor Node Group. Default=AL2_x86_64. For ARM AMIs, use AL2_ARM_64"
  default = "AL2_x86_64"
}

variable "compactor_ami_type" {
  type = string
  description = "Type of Amazon Machine Image (AMI) associated with the Compactor Node Group. Default=AL2_x86_64. For ARM AMIs, use AL2_ARM_64"
  default = "AL2_x86_64"
}

variable "spot_fallback_to_ondemand" {
  type        = bool
  description = "Create fallback ondemand nodegroups for ingestor and compactor nodes"
  default     = false
}

variable "cluster_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for main node-group"
  default     = ["m6a.2xlarge"]
}

variable "artifact_registry_url" {
 type = string
 default = "https://us-central1-docker.pkg.dev"
 description = "Mach5 Artifact registry URL"
}

variable "artifact_registry_username" {
 type = string
 default = "_json_key_base64"
 description = "Username to access Mach5 Artifact registry"
}

variable "namespace" {
 type = string
 default = "mach5"
 description = "Namespace to be used for installing Mach5 Search helmcharts"
}

variable "mach5_helm_release_name" {
 type = string
 default = "m5s"
 description = "Helm release name"
}

variable "mach5_helm_repository" {
 type = string
 default = "oci://us-central1-docker.pkg.dev/mach5-dev/mach5-docker-registry"
 description = "Repository URL where to locate the requested helm chart"
}

variable "mach5_helm_chart_name" {
 type = string
 default = "mach5-search"
 description = "Chart name to be installed"
}

variable "prefix" {
  type        = string
  description = "Mach5 prefix for resources"
  default     = "mach5"
}

variable "cluster_name" {
  default = "mach5-cluster"
  type = string
  description = "AWS EKS Mach5 Cluster"
  nullable = false
}

variable "cluster_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for main node-group"
  default     = 1
}

variable "cluster_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for main node-group"
  default     = 1
}

variable "cluster_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for main node-group"
  default     = 1
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR Block for AWS VPC"
  default     = "10.0.0.0/16"
}

variable "cluster_service_cidr" {
  type        = string
  description = "CIDR Block for Cluster"
  default     = "10.0.0.0/24"
}

variable "ebs_addon_version" {
  type        = string
  description = "Add-on version for the AWS EBS CSI driver"
  default     = "v1.44.0-eksbuild.1"
}

variable "cluster_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for main node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "private_route_table" {
  type        = string
  description = "CIDR block for private subnet route table"
  default     = "0.0.0.0/0"
}

variable "public_route_table" {
  type        = string
  description = "CIDR block for public subnet route table"
  default     = "0.0.0.0/0"
}

variable "private-subnet-cidr-1" {
  type        = string
  description = "CIDR block for private subnet 1"
  default     = "10.0.0.0/19"
}

variable "private-subnet-zone-1" {
  type        = string
  description = "Availability zone for private subnet 1"
  default     = "us-east-1a"
}

variable "private-subnet-cidr-2" {
  type        = string
  description = "CIDR block for private subnet 2"
  default     = "10.0.32.0/19"
}

variable "private-subnet-zone-2" {
  type        = string
  description = "Availability zone for private subnet 2"
  default     = "us-east-1b"
}

variable "public-subnet-cidr-1" {
  type        = string
  description = "CIDR block for public subnet 1"
  default     = "10.0.64.0/19"
}

variable "public-subnet-zone-1" {
  type        = string
  description = "Availability zone for public subnet 1"
  default     = "us-east-1a"
}

variable "public-subnet-cidr-2" {
  type        = string
  description = "CIDR block for private subnet 2"
  default     = "10.0.96.0/19"
}

variable "public-subnet-zone-2" {
  type        = string
  description = "Availability zone for public subnet 2"
  default     = "us-east-1b"
}

variable "ingestor_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for ingestor node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "ingestor_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for ingestor node-group"
  default     = 0
}

variable "ingestor_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for ingestor node-group"
  default     = 0
}

variable "ingestor_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for ingestor node-group"
  default     = 10
}

variable "ingestor_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for ingestor node-group"
  default     = ["m6id.2xlarge"]
}

variable "ondemand_ingestor_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for on-demand ingestor node-group"
  default     = 0
}

variable "ondemand_ingestor_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for on-demand ingestor node-group"
  default     = 0
}

variable "ondemand_ingestor_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for on-demand ingestor node-group"
  default     = 1
}

variable "ondemand_ingestor_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for on-demand ingestor node-group"
  default     = ["m6id.2xlarge"]
}

variable "compactor_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for compactor node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "compactor_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for compactor node-group"
  default     = 0
}

variable "compactor_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for compactor node-group"
  default     = 0
}

variable "compactor_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for compactor node-group"
  default     = 10
}

variable "compactor_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for compactor node-group"
  default     = ["m6id.2xlarge"]
}

variable "ondemand_compactor_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for on-demand compactor node-group"
  default     = 0
}

variable "ondemand_compactor_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for on-demand compactor node-group"
  default     = 0
}

variable "ondemand_compactor_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for on-demand compactor node-group"
  default     = 1
}

variable "ondemand_compactor_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for on-demand compactor node-group"
  default     = ["m6id.2xlarge"]
}

variable "warehouse_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for warehouse node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "warehouse_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for warehouse node-group"
  default     = 0
}

variable "warehouse_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for warehouse node-group"
  default     = 0
}

variable "warehouse_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for warehouse node-group"
  default     = 10
}

variable "warehouse_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for warehouse node-group"
  default     = ["i4i.2xlarge"]
}

variable "warehouse_head_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for warehouse node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "warehouse_head_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for warehouse node-group"
  default     = 0
}

variable "warehouse_head_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for warehouse node-group"
  default     = 0
}

variable "warehouse_head_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for warehouse node-group"
  default     = 10
}

variable "warehouse_head_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for warehouse node-group"
  default     = ["t3a.2xlarge"]
}

variable "fdb_node_capacity_type" {
  type        = string
  description = "Node capacity type to be used for cstorecacheserver node-group (ON_DEMAND/SPOT)"
  default     = "ON_DEMAND"
}

variable "fdb_node_desired_size" {
  type        = number
  description = "Desired number of nodes used for cstorecacheserver node-group"
  default     = 1
}

variable "fdb_node_min_size" {
  type        = number
  description = "Minimum number of nodes used for cstorecacheserver node-group"
  default     = 1
}

variable "fdb_node_max_size" {
  type        = number
  description = "Maximum number of nodes used for cstorecacheserver node-group"
  default     = 5
}

variable "fdb_node_instance_type" {
  type        = list(string)
  description = "EC2 machine type to be used for cstorecacheserver node-group"
  default     = ["m6a.4xlarge"]
}

variable "cache_proxy_version" {
  type        = string
  description = "Version for the mach5 cache proxy helm chart"
  default     = "1.13.1"
}

variable "log_max_size" {
  type        = string
  description = "Maximum size of the log file for a container before it is rotated"
  default     = "20Mi"
}

variable "log_max_files" {
  type        = string
  description = "Maximum number of rotated log files to keep for each container"
  default     = "2"
}

variable "storageclass_name" {
  type = string
  description = "Name of the gp3 storage class"
  default = "gp3"
}

variable "storageclass_provisioner" {
  type = string
  description = "Storage class provisioner"
  default = "ebs.csi.aws.com"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default = "mach5-cluster-sa"
}