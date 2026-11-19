resource "aws_wafv2_web_acl" "cloudfront" {
  count    = local.enable_cloudfront_waf ? 1 : 0
  provider = aws.us-east-1

  name        = local.cloudfront_waf_name
  description = "Managed WAF rules for the ${var.wagtail_domain} CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }


  # The app's own limits are per process, so this is the one to rely on.
  # Its action ignores waf_monitor_mode, which is for the managed rule groups.
  dynamic "rule" {
    for_each = local.enable_ai ? [1] : []

    content {
      name     = "ai-rate-limit"
      priority = 5

      action {
        dynamic "block" {
          for_each = var.ai_rate_limit_action == "block" ? [1] : []
          content {
            custom_response {
              response_code = 429
            }
          }
        }

        dynamic "count" {
          for_each = var.ai_rate_limit_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit                 = var.ai_rate_limit
          aggregate_key_type    = "IP"
          evaluation_window_sec = 300

          scope_down_statement {
            or_statement {
              dynamic "statement" {
                for_each = ["/mcp", "/search/ai/"]

                content {
                  byte_match_statement {
                    search_string         = statement.value
                    positional_constraint = "STARTS_WITH"

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "cloudfront-aiRateLimit"
        sampled_requests_enabled   = true
      }
    }
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

          dynamic "rule_action_override" {
            for_each = rule.value.name == "AWSManagedRulesCommonRuleSet" && local.waf_sizerestriction_action_override != "none" ? local.waf_common_rule_set_sizerestriction_rules : []

            content {
              name = rule_action_override.value

              action_to_use {
                dynamic "count" {
                  for_each = local.waf_sizerestriction_action_override == "count" ? [1] : []
                  content {}
                }
              }
            }
          }
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
