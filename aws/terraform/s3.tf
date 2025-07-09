locals {
  mach5_s3_log_prefix   = "logs"
  mach5_s3_store_prefix = "store"
}

### S3 Bucket for Mach5

resource "aws_s3_bucket" "mach5_s3_bucket" {
  bucket = var.mach5_s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "mach5_s3_bucket" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mach5_s3_bucket" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mach5_s3_bucket" {
  bucket                  = aws_s3_bucket.mach5_s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "mach5_s3_bucket_policy" {
  statement {
    sid    = "EnforceHttps"
    effect = "Deny"

    actions = [
      "s3:*"
    ]

    principals {
      identifiers = ["*"]
      type        = "*"
    }
    resources = [
      aws_s3_bucket.mach5_s3_bucket.arn,
      "${aws_s3_bucket.mach5_s3_bucket.arn}/*"
    ]

    condition {
      test     = "Bool"
      values   = ["false"]
      variable = "aws:SecureTransport"
    }
  }
}

resource "aws_s3_bucket_policy" "mach5_s3_bucket_policy" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id
  policy = data.aws_iam_policy_document.mach5_s3_bucket_policy.json
}

### S3 Bucket SubFolders

resource "aws_s3_object" "mach5_s3_log_path" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id
  key    = "${local.mach5_s3_log_prefix}/"
  source = "/dev/null"
}

resource "aws_s3_object" "mach5_s3_store_path" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id
  key    = "${local.mach5_s3_store_prefix}/"
  source = "/dev/null"
}

resource "aws_s3_bucket_lifecycle_configuration" "abort_incomplete_multipart_upload" {
  bucket = aws_s3_bucket.mach5_s3_bucket.id

  rule {
    id = "abort-incomplete-multipart-upload"
    status = "Enabled"
    filter {
      prefix = "" # Apply to all objects
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [ aws_s3_bucket.mach5_s3_bucket ]
}