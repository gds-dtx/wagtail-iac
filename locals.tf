locals {
  task_name = "wagtail-${var.wagtail_instance_id}"

  ssm_key_prefix  = "/wagtail/${var.environment_name}/${var.wagtail_instance_id}"
  ssm_oidc_secret = "${local.ssm_key_prefix}/oidc_secret"

  # Days must be one of: 0 1 3 5 7 14 30 60 90 120 150 180 365 400 545 731 1096 1827 2192 2557 2922 3288 3653
  wagtail_log_retention_days    = var.environment_name == "production" ? 365 : 14
  cloudfront_log_retention_days = var.environment_name == "production" ? 1096 : 14

  # Media S3 requires the CloudFront distribution (bootstrap_step >= 1) for the /media/* behaviour and OAC bucket policy.
  enable_media_s3   = var.enable_media_s3 && var.bootstrap_step >= 1
  media_bucket_name = var.media_bucket_name != "" ? var.media_bucket_name : "${local.task_name}-media-${var.environment_name}"

  # The MCP server: its own ECS service, behind the site's listener at /mcp.
  enable_mcp        = var.enable_mcp && var.bootstrap_step >= 2
  mcp_task_name     = "${local.task_name}-mcp"
  mcp_port          = 8001
  mcp_desired_count = coalesce(var.mcp_desired_count, var.desired_count)
  # Target group names are limited to 32 characters; "wagtail-<id>-mcp-tg" can pass that.
  mcp_target_group_name = "mcp-${var.wagtail_instance_id}"

  # Ask: its summary is served by the MCP server's service, so it needs it.
  enable_ask     = var.enable_ask && local.enable_mcp
  bedrock_region = coalesce(var.bedrock_region, data.aws_region.current.region)
  # The model an inference profile names, without the profile's prefix:
  # "eu.anthropic.claude-opus-5-5" is "anthropic.claude-opus-5-5".
  ask_claude_foundation_model = replace(var.ask_claude_model, "/^(eu|us|apac|jp|au|global)\\./", "")

  enable_cloudfront_access_log_delivery            = var.enable_cloudfront_access_logs && var.bootstrap_step >= 1
  enable_cloudfront_waf                            = var.enable_cloudfront_waf && var.bootstrap_step >= 1
  cloudfront_access_logs_log_group_name            = "${local.task_name}-cf-access-logs"
  cloudfront_access_logs_delivery_source_name      = substr("${local.task_name}-cf-logs-src", 0, 60)
  cloudfront_access_logs_delivery_destination_name = substr("${local.task_name}-cf-logs-dst", 0, 60)
  cloudfront_viewer_request_function_name          = substr("${local.task_name}-viewer-request", 0, 64)
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
  waf_sizerestriction_action_override = lower(var.sizerestriction_action_override)
  waf_common_rule_set_sizerestriction_rules = [
    "SizeRestrictions_QUERYSTRING",
    "SizeRestrictions_Cookie_HEADER",
    "SizeRestrictions_BODY",
    "SizeRestrictions_URIPATH",
  ]

  database_username = sensitive(random_password.sql_master_username.result)
  database_password = sensitive(random_password.sql_master_password.result)
  database_name     = sensitive("db${random_password.sql_database_name.result}")

  # Gunicorn reads WEB_CONCURRENCY as its worker count. Derived from task_cpu
  # rather than in the image, because on Fargate os.cpu_count() reports the
  # host's CPUs, not the task's share.
  web_concurrency = coalesce(var.web_concurrency, max(1, floor(var.task_cpu / 512)))

  wagtail_variables = merge(
    { WEB_CONCURRENCY = tostring(local.web_concurrency) },
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
    },
    # Media served from the same origin via the /media/* CloudFront behaviour,
    # so MEDIA_S3_CUSTOM_DOMAIN is the site domain (img-src 'self' already covers it).
    local.enable_media_s3 ? {
      MEDIA_S3_BUCKET        = local.media_bucket_name
      MEDIA_S3_REGION        = data.aws_region.current.region
      MEDIA_S3_CUSTOM_DOMAIN = var.wagtail_domain
      MEDIA_S3_LOCATION      = var.media_s3_location
    } : {},
    # On every container: the site writes the content index as editors publish,
    # the MCP server reads it, and the scheduled tasks keep it current. The MCP
    # server will not start without it.
    local.enable_mcp ? { FEATURE_MCP = "true" } : {},
    # The address the MCP server's rate limit counts. Only once the viewer
    # request function is attached (bootstrap_step 3), which overwrites
    # true-client-ip with the viewer's own address: before that CloudFront
    # forwards whatever the client sent, and a client could pick its own.
    local.enable_mcp && var.bootstrap_step >= 3 ? { MCP_CLIENT_IP_HEADER = "true-client-ip" } : {},
    # Ask, on every container: the site answers /ask/ and embeds each
    # question, the MCP service writes the summary, and the nightly rebuild
    # embeds the content index. Its rate limits count the same header as the
    # MCP server's (the app's CLIENT_IP_HEADER defaults to it).
    local.enable_ask ? {
      FEATURE_ASK                    = "true"
      CONTENT_INDEX_EMBEDDINGS       = "bedrock"
      CONTENT_INDEX_EMBEDDING_REGION = local.bedrock_region
      ASK_CLAUDE                     = var.ask_claude_endpoint == "bedrock-mantle" ? "bedrock-mantle" : "bedrock"
      ASK_CLAUDE_MODEL               = var.ask_claude_model
      ASK_CLAUDE_REGION              = local.bedrock_region
      ASK_DAILY_TOKEN_BUDGET         = tostring(var.ask_daily_token_budget)
    } : {}
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
