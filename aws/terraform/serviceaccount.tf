
resource "aws_iam_role" "marketplace_metering" {
  name = "${var.prefix}-eks-marketplace-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "marketplace_metering_full_access" {
  role       = aws_iam_role.marketplace_metering.name
  policy_arn = "arn:aws:iam::aws:policy/AWSMarketplaceMeteringFullAccess"
}

resource "aws_iam_role_policy_attachment" "marketplace_metering_register_usage" {
  role       = aws_iam_role.marketplace_metering.name
  policy_arn = "arn:aws:iam::aws:policy/AWSMarketplaceMeteringRegisterUsage"
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.marketplace_metering.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "kubernetes_service_account" "marketplace_metering" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.marketplace_metering.arn
    }
  }
}
