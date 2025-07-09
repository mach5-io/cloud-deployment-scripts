##################
# S3 Endpoint
##################

resource "aws_vpc_endpoint" "s3_endpoint" {
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_id       = local.vpc_id
  tags = {
    Name = "Mach5 S3 Endpoint - ${var.prefix}"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_public" {
  route_table_id  = aws_route_table.public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  route_table_id  = aws_route_table.private.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}