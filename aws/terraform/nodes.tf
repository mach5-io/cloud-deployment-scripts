locals {
  eks_asg_tag_list_main_nodes = {
    "Name" = "${var.prefix}-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-main-role" = "true"
  }
  eks_asg_tag_list_ccs_nodes = {
    "Name" = "${var.prefix}-ccs-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ccs-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ccs-role" = "true"
  }
  eks_asg_tag_list_ingestor_nodes = {
    "Name" = "${var.prefix}-ingestor-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ingestor-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ingestor-role" = "true"
  }
  eks_asg_tag_list_compactor_nodes = {
    "Name" = "${var.prefix}-compactor-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-compactor-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-compactor-role" = "true"
  }
  eks_asg_tag_list_warehouse_nodes = {
    "Name" = "${var.prefix}-warehouse-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-warehouse-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-warehouse-worker-role" = "true"
  }
  eks_asg_tag_list_warehouse_head_nodes = {
    "Name" = "${var.prefix}-warehouse-head-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-warehouse-head-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-warehouse-head-role" = "true"
  }
  eks_asg_tag_list_ingestor_nodes_demand = {
    "Name" = "${var.prefix}-ondemand-ingest-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ondemand-ingest-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ingestor-role" = "true"
  }
  eks_asg_tag_list_compactor_nodes_demand = {
    "Name" = "${var.prefix}-ondemand-compact-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ondemand-compact-nodes"
    "k8s.io/cluster-autoscaler/node-template/label/mach5-compactor-role" = "true"
  }
}

resource "aws_iam_role" "mach5-nodes" {
  name = "${var.prefix}-group-nodes"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.mach5-nodes.name
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.mach5-nodes.name
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.mach5-nodes.name
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonS3FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.mach5-nodes.name
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.mach5-nodes.name
}

module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.cluster_node_min_size
  max_size     = var.cluster_node_max_size
  desired_size = var.cluster_node_desired_size
  capacity_type  = var.cluster_node_capacity_type
  instance_types = var.cluster_node_instance_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = data.aws_ami.x86_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT

  labels = {
    mach5-main-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-main-role" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}

resource "aws_autoscaling_group_tag" "main-nodes" {
  for_each               = local.eks_asg_tag_list_main_nodes
  autoscaling_group_name = module.eks_managed_node_group.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

module "eks_managed_node_group_ingestor" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-ingestor-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.ingestor_node_min_size
  max_size     = var.ingestor_node_max_size
  desired_size = var.ingestor_node_desired_size
  capacity_type  = var.ingestor_node_capacity_type
  instance_types = var.ingestor_node_instance_type
  ami_type = var.ingestor_ami_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = var.ingestor_ami_type == "AL2_x86_64" ? data.aws_ami.x86_ami.id  : data.aws_ami.arm_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT
  
  labels = {
    mach5-ingestor-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ingestor-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ingestor-role" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}

module "eks_managed_node_group_ingestor_ondemand" {
  count = var.spot_fallback_to_ondemand ? 1 : 0
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-ondemand-ingest-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.ondemand_ingestor_node_min_size
  max_size     = var.ondemand_ingestor_node_max_size
  desired_size = var.ondemand_ingestor_node_desired_size
  capacity_type  = "ON_DEMAND"
  instance_types = var.ondemand_ingestor_node_instance_type
  ami_type = var.ingestor_ami_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = var.ingestor_ami_type == "AL2_x86_64" ? data.aws_ami.x86_ami.id  : data.aws_ami.arm_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT
  
  labels = {
    mach5-ingestor-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ondemand-ingest-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ingestor-role" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}

resource "aws_autoscaling_group_tag" "ingestor-nodes" {
  for_each               = local.eks_asg_tag_list_ingestor_nodes
  autoscaling_group_name = module.eks_managed_node_group_ingestor.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "ingestor-nodes-demand" {
  for_each               = var.spot_fallback_to_ondemand ? local.eks_asg_tag_list_ingestor_nodes_demand: {}
  autoscaling_group_name = var.spot_fallback_to_ondemand ? module.eks_managed_node_group_ingestor_ondemand.0.node_group_autoscaling_group_names.0 : ""

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

module "eks_managed_node_group_compactor" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-compactor-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.compactor_node_min_size
  max_size     = var.compactor_node_max_size
  desired_size = var.compactor_node_desired_size
  capacity_type  = var.compactor_node_capacity_type
  instance_types = var.compactor_node_instance_type
  ami_type = var.compactor_ami_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = var.compactor_ami_type == "AL2_x86_64" ? data.aws_ami.x86_ami.id  : data.aws_ami.arm_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT
  
  labels = {
    mach5-compactor-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-compactor-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-compactor-role" = "true",
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}

module "eks_managed_node_group_compactor_ondemand" {
  count = var.spot_fallback_to_ondemand ? 1 : 0
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-ondemand-compact-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.ondemand_compactor_node_min_size
  max_size     = var.ondemand_compactor_node_max_size
  desired_size = var.ondemand_compactor_node_desired_size
  capacity_type  = "ON_DEMAND"
  instance_types = var.ondemand_compactor_node_instance_type
  ami_type = var.compactor_ami_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = var.compactor_ami_type == "AL2_x86_64" ? data.aws_ami.x86_ami.id  : data.aws_ami.arm_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT
  
  labels = {
    mach5-compactor-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ondemand-compact-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-compactor-role" = "true",
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}

resource "aws_autoscaling_group_tag" "compactor-nodes" {
  for_each               = local.eks_asg_tag_list_compactor_nodes
  autoscaling_group_name = module.eks_managed_node_group_compactor.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "compactor-nodes-demand" {
  for_each               = var.spot_fallback_to_ondemand ? local.eks_asg_tag_list_compactor_nodes_demand : {}
  autoscaling_group_name = var.spot_fallback_to_ondemand ? module.eks_managed_node_group_compactor_ondemand.0.node_group_autoscaling_group_names.0 : ""

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

module "eks_managed_node_group_warehouse" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-warehouse-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.warehouse_node_min_size
  max_size     = var.warehouse_node_max_size
  desired_size = var.warehouse_node_desired_size
  capacity_type  = var.warehouse_node_capacity_type
  instance_types = var.warehouse_node_instance_type
  ami_type = var.warehouse_ami_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = var.warehouse_ami_type == "AL2_x86_64" ? data.aws_ami.x86_ami.id  : data.aws_ami.arm_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT

  labels = {
    mach5-warehouse-worker-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-warehouse-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-warehouse-worker-role" = "true",
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}
resource "aws_autoscaling_group_tag" "warehouse-nodes" {
  for_each               = local.eks_asg_tag_list_warehouse_nodes
  autoscaling_group_name = module.eks_managed_node_group_warehouse.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

module "eks_managed_node_group_warehouse_head" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-warehouse-head-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.warehouse_head_node_min_size
  max_size     = var.warehouse_head_node_max_size
  desired_size = var.warehouse_head_node_desired_size
  capacity_type  = var.warehouse_head_node_capacity_type
  instance_types = var.warehouse_head_node_instance_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = data.aws_ami.x86_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT

  labels = {
    mach5-warehouse-head-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-warehouse-head-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-warehouse-head-role" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}
resource "aws_autoscaling_group_tag" "warehouse-head-nodes" {
  for_each               = local.eks_asg_tag_list_warehouse_head_nodes
  autoscaling_group_name = module.eks_managed_node_group_warehouse_head.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}

module "eks_managed_node_group_ccs" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.37.2"
  name            = "${var.prefix}-ccs-nodes"
  cluster_name    = aws_eks_cluster.mach5-cluster.name
  subnet_ids = [aws_subnet.private-us-east-1a.id]
  create_iam_role = false
  iam_role_arn = aws_iam_role.mach5-nodes.arn
  create = true
  cluster_service_cidr = var.cluster_service_cidr
  min_size     = var.ccs_node_min_size
  max_size     = var.ccs_node_max_size
  desired_size = var.ccs_node_desired_size
  capacity_type  = var.ccs_node_capacity_type
  instance_types = var.ccs_node_instance_type

  update_config = {
    max_unavailable = 1
  }

  cluster_primary_security_group_id = aws_eks_cluster.mach5-cluster.vpc_config[0].cluster_security_group_id

  ami_id = data.aws_ami.x86_ami.id
  enable_bootstrap_user_data = true

  pre_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    setup-local-disks raid0
  EOT

  post_bootstrap_user_data = <<-EOT
    #!/usr/bin/env bash
    SRC_CONF="/etc/systemd/system/kubelet.service.d/30-kubelet-extra-args.conf"
    DST_CONF="/etc/systemd/system/kubelet.service.d/40-kubelet-extra-args.conf"
    if [ -f "$SRC_CONF" ]; then
      content=$(cat "$SRC_CONF")
      modified_content=$(echo "$content" | sed "s/'\$/ --container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}'/")
      echo "$modified_content" | tee "$DST_CONF"
    else
      echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.log_max_size} --container-log-max-files=${var.log_max_files}"
        ' | tee $DST_CONF
    fi
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart kubelet
  EOT

  labels = {
    mach5-ccs-role = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.mach5-cluster.name}" = "owned",
    "k8s.io/cluster-autoscaler/enabled"             = "true",
    "k8s.io/cluster-autoscaler/node-template/label/group" = "${var.prefix}-ccs-nodes",
    "k8s.io/cluster-autoscaler/node-template/label/mach5-ccs-role" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mach5-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.mach5-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.mach5-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.mach5-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.mach5-AmazonEC2FullAccess,
  ]
}
resource "aws_autoscaling_group_tag" "ccs-nodes" {
  for_each               = local.eks_asg_tag_list_ccs_nodes
  autoscaling_group_name = module.eks_managed_node_group_ccs.node_group_autoscaling_group_names.0

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}