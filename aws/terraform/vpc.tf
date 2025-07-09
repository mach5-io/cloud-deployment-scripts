resource "aws_vpc" "mach5-vpc" {
  count = var.existing_vpc_id == "" ? 1 : 0
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "${var.prefix}-vpc"
  }

  enable_dns_hostnames = true
}

resource "aws_default_security_group" "mach5_vpc_default_sg" {
  count = var.existing_vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.mach5-vpc[0].id
}

locals {
  vpc_id = var.existing_vpc_id != "" ? var.existing_vpc_id : aws_vpc.mach5-vpc[0].id
}
