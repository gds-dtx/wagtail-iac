locals {
  task_name = "wagtail-${var.wagtail_instance_id}"

  ssm_key_prefix  = "/wagtail/${var.environment_name}/${var.wagtail_instance_id}"
  ssm_oidc_secret = "${local.ssm_key_prefix}/oidc_secret"

  wagtail_log_retention_days    = var.environment_name == "production" ? 365 : 14
  cloudfront_log_retention_days = var.environment_name == "production" ? 740 : 14

  enable_cloudfront_access_log_delivery            = var.enable_cloudfront_access_logs && var.bootstrap_step >= 1
  enable_cloudfront_waf                            = var.enable_cloudfront_waf && var.bootstrap_step >= 1
  cloudfront_access_logs_log_group_name            = "${local.task_name}-cf-access-logs"
  cloudfront_access_logs_delivery_source_name      = substr("${local.task_name}-cf-logs-src", 0, 60)
  cloudfront_access_logs_delivery_destination_name = substr("${local.task_name}-cf-logs-dst", 0, 60)
  cloudfront_waf_name                              = substr("${local.task_name}-cf-waf", 0, 60)

  waf_managed_rule_groups = [
    {
      name        = "AWSManagedRulesAmazonIpReputationList"
      vendor_name = "AWS"
      priority    = 10
      metric_name = "amazonIpReputation"
    },
    {
      name        = "AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name = "AWS"
      priority    = 20
      metric_name = "knownBadInputs"
    },
    {
      name        = "AWSManagedRulesCommonRuleSet"
      vendor_name = "AWS"
      priority    = 30
      metric_name = "commonRuleSet"
    },
    {
      name        = "AWSManagedRulesLinuxRuleSet"
      vendor_name = "AWS"
      priority    = 40
      metric_name = "linuxRuleSet"
    },
    {
      name        = "AWSManagedRulesSQLiRuleSet"
      vendor_name = "AWS"
      priority    = 50
      metric_name = "sqliRuleSet"
    },
  ]

  database_username = sensitive(random_password.sql_master_username.result)
  database_password = sensitive(random_password.sql_master_password.result)
  database_name     = sensitive("db${random_password.sql_database_name.result}")
  wagtail_variables = merge(
    var.wagtail_variables,
    {
      DOMAIN                       = var.wagtail_domain
      BASE_URL                     = "https://${var.wagtail_domain}"
      DATABASE_NAME                = local.database_name
      DATABASE_USER                = local.database_username
      DATABASE_HOST                = aws_rds_cluster.db.endpoint
      LOG_LEVEL                    = var.log_level
      TRUST_PROXY                  = "true"
      TOKEN_EXPIRES_IN             = tostring(var.token_expires_in)
      DEFAULT_LANGUAGE             = "en-GB"
      SMTP_HOST                    = "127.0.0.1"
      SMTP_PORT                    = "2525"
      SMTP_SECURE                  = "false"
      SMTP_TLS_REJECT_UNAUTHORIZED = "false"
      DJANGO_SETTINGS_MODULE       = var.django_settings_module
    }
  )
}

resource "aws_secretsmanager_secret" "secret_key" {
  name        = "${local.ssm_key_prefix}/secret_key"
  description = "Django SECRET_KEY for ${local.task_name}"
}

resource "aws_secretsmanager_secret_version" "secret_key" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = random_password.wagtail-secret-key.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "wagtail-secret-key" {
  length  = 24
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [
      length,
      special,
      upper,
    ]
  }
}
