resource "aws_iam_role" "mach5-role" {
  name = "${var.prefix}-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "mach5-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.mach5-role.name
}

resource "aws_eks_cluster" "mach5-cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.mach5-role.arn
  version = "1.32"

  vpc_config {
    subnet_ids = [
      aws_subnet.private-us-east-1a.id,
      aws_subnet.private-us-east-1b.id,
      aws_subnet.public-us-east-1a.id,
      aws_subnet.public-us-east-1b.id
    ]
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.mach5-AmazonEKSClusterPolicy]
}

### OIDC config
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.mach5-cluster.identity.0.oidc.0.issuer
}
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates.0.sha1_fingerprint]
  url = aws_eks_cluster.mach5-cluster.identity.0.oidc.0.issuer
}

data "aws_ami" "x86_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.32-v20250610"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["602401143452"]
}

data "aws_ami" "arm_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-arm64-node-1.32-v20250610"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  owners = ["602401143452"]
}
