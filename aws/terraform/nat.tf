resource "aws_eip" "mach5-nat" {
  domain = "vpc"

  tags = {
    Name = "${var.prefix}-nat"
  }
}

resource "aws_nat_gateway" "mach5-nat" {
  allocation_id = aws_eip.mach5-nat.id
  subnet_id     = aws_subnet.public-us-east-1a.id

  tags = {
    Name = "${var.prefix}-nat"
  }

  depends_on = [aws_internet_gateway.mach5-igw]
}