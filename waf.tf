resource "aws_wafv2_web_acl" "cloudfront" {
  count    = local.enable_cloudfront_waf ? 1 : 0
  provider = aws.us-east-1

  name        = local.cloudfront_waf_name
  description = "Managed WAF rules for the ${var.wagtail_domain} CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "count" {
          for_each = var.waf_monitor_mode ? [1] : []
          content {}
        }

        dynamic "none" {
          for_each = var.waf_monitor_mode ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "cloudfront-${rule.value.metric_name}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cloudfrontWebAcl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = local.cloudfront_waf_name
  }
}
