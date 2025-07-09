resource "aws_subnet" "private-us-east-1a" {
  vpc_id            = local.vpc_id
  cidr_block        = var.private-subnet-cidr-1
  availability_zone = var.private-subnet-zone-1

  tags = {
    "Name"                            = "${var.prefix}-private-${var.private-subnet-zone-1}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}"      = "owned"
  }
}

resource "aws_subnet" "private-us-east-1b" {
  vpc_id            = local.vpc_id
  cidr_block        = var.private-subnet-cidr-2
  availability_zone = var.private-subnet-zone-2

  tags = {
    "Name"                            = "${var.prefix}-private-${var.private-subnet-zone-2}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}"      = "owned"
  }
}

resource "aws_subnet" "public-us-east-1a" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.public-subnet-cidr-1
  availability_zone       = var.public-subnet-zone-1
  map_public_ip_on_launch = true

  tags = {
    "Name"                       = "${var.prefix}-public-${var.public-subnet-zone-1}"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "public-us-east-1b" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.public-subnet-cidr-2
  availability_zone       = var.public-subnet-zone-2
  map_public_ip_on_launch = true

  tags = {
    "Name"                       = "${var.prefix}-public-${var.public-subnet-zone-2}"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}