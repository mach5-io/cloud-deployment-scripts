#Network VPC-ID already has an internet gateway attached
resource "aws_internet_gateway" "mach5-igw" {
  count = var.existing_vpc_id == "" ? 1 : 0
  vpc_id = local.vpc_id

  tags = {
    Name = "${var.prefix}-igw"
  }
}

locals {
  igw_id = var.existing_vpc_id != "" ? var.igw_id : aws_internet_gateway.mach5-igw[0].id
}