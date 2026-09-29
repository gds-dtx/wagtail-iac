# S3 bucket for Wagtail media (user uploads / documents), served through the
# existing CloudFront distribution via a /media/* behaviour using Origin Access
# Control. Objects stay private; only CloudFront can read them.

resource "aws_s3_bucket" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = local.media_bucket_name

  tags = {
    Name = "${local.task_name}-media"
  }
}

resource "aws_s3_bucket_versioning" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = aws_s3_bucket.media[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = aws_s3_bucket.media[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Access to media comes via CloudFront OAC, never object ACLs.
resource "aws_s3_bucket_ownership_controls" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = aws_s3_bucket.media[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = aws_s3_bucket.media[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Origin Access Control lets the CloudFront distribution sign requests to the
# private S3 origin (SigV4). No object ACLs or public bucket policy needed.
resource "aws_cloudfront_origin_access_control" "media" {
  count = local.enable_media_s3 ? 1 : 0

  name                              = substr("${local.task_name}-media-oac", 0, 64)
  description                       = "OAC for ${local.task_name} media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "media_bucket" {
  count = local.enable_media_s3 ? 1 : 0

  # Reject any non-TLS access.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.media[0].arn,
      "${aws_s3_bucket.media[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow only this CloudFront distribution to read objects.
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media[0].arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "media" {
  count  = local.enable_media_s3 ? 1 : 0
  bucket = aws_s3_bucket.media[0].id
  policy = data.aws_iam_policy_document.media_bucket[0].json

  # The bucket policy references the distribution ARN; the public access block
  # must be in place first so block_public_policy does not reject it.
  depends_on = [aws_s3_bucket_public_access_block.media]
}
