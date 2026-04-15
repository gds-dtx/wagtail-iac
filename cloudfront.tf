data "aws_cloudfront_origin_request_policy" "origin" {
  name = "Managed-AllViewerAndCloudFrontHeaders-2022-06"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "random_password" "cloudfront_origin_header" {
  length  = 16
  special = false
  upper   = false
  numeric = false

  lifecycle {
    ignore_changes = [
      length,
      special,
      upper,
      numeric,
    ]
  }
}

resource "aws_cloudfront_distribution" "this" {
  count = var.bootstrap_step >= 1 ? 1 : 0

  origin {
    domain_name = aws_route53_record.alb[0].fqdn
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = var.port
      https_port             = var.port
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-ALB-Protection"
      value = random_password.cloudfront_origin_header.result
    }

    custom_header {
      name  = "X-Forwarded-Port"
      value = "443"
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = var.wagtail_domain
  http_version    = "http2and3"
  web_acl_id      = local.enable_cloudfront_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null

  aliases = var.bootstrap_step >= 3 ? [var.wagtail_domain] : []

  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.origin.id
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # "whitelist"
      # locations        = ["GB"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.bootstrap_step >= 3 ? false : true
    acm_certificate_arn            = var.bootstrap_step >= 3 ? aws_acm_certificate_validation.cloudfront_cert[0].certificate_arn : null
    ssl_support_method             = var.bootstrap_step >= 3 ? "sni-only" : null
    minimum_protocol_version       = var.bootstrap_step >= 3 ? "TLSv1.2_2021" : null
  }

  tags = {
    Name = "${local.task_name}-cloudfront-distribution"
  }
}

# CloudFront standard logging v2 to CloudWatch Logs is anchored in us-east-1.
resource "aws_cloudwatch_log_delivery_source" "cloudfront_access" {
  count    = local.enable_cloudfront_access_log_delivery ? 1 : 0
  provider = aws.us-east-1

  name         = local.cloudfront_access_logs_delivery_source_name
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this[0].arn

  tags = {
    Name = local.cloudfront_access_logs_delivery_source_name
  }
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_access" {
  count    = local.enable_cloudfront_access_log_delivery ? 1 : 0
  provider = aws.us-east-1

  name          = local.cloudfront_access_logs_delivery_destination_name
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.cloudfront_access[0].arn
  }

  depends_on = [
    aws_cloudwatch_log_group.cloudfront_access
  ]

  tags = {
    Name = local.cloudfront_access_logs_delivery_destination_name
  }
}

resource "aws_cloudwatch_log_delivery" "cloudfront_access" {
  count    = local.enable_cloudfront_access_log_delivery ? 1 : 0
  provider = aws.us-east-1

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront_access[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_access[0].arn
  record_fields            = var.cloudfront_access_log_record_fields

  tags = {
    Name = local.cloudfront_access_logs_delivery_destination_name
  }
}
