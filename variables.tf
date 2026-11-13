variable "bootstrap_step" {
  description = "Flag to bootstrap Route53 zone and records, set to false once the zone is created"
  type        = number
  default     = 1
}

variable "wagtail_instance_id" {
  description = "The ID of the wagtail instance"
  type        = string
}

variable "wagtail_domain" {
  description = "The domain of the wagtail instance"
  type        = string
}

variable "cluster_name" {
  description = "The name of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC where the ECS cluster is created"
  type        = string
}

variable "environment_name" {
  description = "The name of the environment (e.g., development, staging, production)"
  type        = string
}

variable "task_memory" {
  description = "The amount of memory (in MiB) to allocate for the ECS task"
  type        = number
  default     = 2048
}

variable "task_cpu" {
  description = "The amount of CPU units to allocate for the ECS task"
  type        = number
  default     = 1024
}

variable "web_concurrency" {
  description = "Number of gunicorn workers per task (WEB_CONCURRENCY). Null derives it from task_cpu: two per vCPU, minimum one."
  type        = number
  default     = null

  validation {
    condition     = var.web_concurrency == null || try(var.web_concurrency >= 1 && floor(var.web_concurrency) == var.web_concurrency, false)
    error_message = "web_concurrency must be null or a whole number of at least 1."
  }
}

variable "efs_id" {
  description = "The ID of the EFS file system to use for persistent storage"
  type        = string
}

variable "port" {
  description = "The port on which the application will listen"
  type        = number
  default     = 8000
}

variable "token_expires_in" {
  description = "The duration for which tokens are valid in days"
  type        = number
  default     = 1
}

variable "image" {
  description = "The base Docker image for the wagtail application"
  type        = string
  default     = "ghcr.io/wagtailnban/wagtail"
}

variable "image_tag" {
  description = "The tag of the wagtail Docker image to use"
  type        = string
  default     = "latest"
}

variable "log_level" {
  description = "The log level for the wagtail application"
  type        = string
  default     = "info"
}

variable "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  type        = string
}

variable "alb_security_group_id" {
  description = "The security group ID for the Application Load Balancer"
  type        = string
}

variable "desired_count" {
  description = "The desired number of ECS task instances"
  type        = number
  default     = 1
}

variable "wagtail_variables" {
  description = "Additional environment variables for the wagtail application"
  type        = map(string)
  default     = {}
}

variable "django_settings_module" {
  description = "The Django settings module to use for the wagtail application"
  type        = string
  default     = "govuk.settings.production"
}

variable "route53_zone_id" {
  description = "The ID of the Route53 hosted zone"
  type        = string
  default     = ""
}

variable "enable_caa_records" {
  description = "Create Route53 CAA records for the domain and www authorizing Amazon to issue ACM certificates when bootstrap_step >= 2"
  type        = bool
  default     = true
}

variable "create_ssm_parameters" {
  description = "Flag to enable creation of SSM parameters"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Flag to enable ECS execute command feature"
  type        = bool
  default     = false
}

variable "enable_cloudfront_access_logs" {
  description = "Flag to enable CloudFront standard access logs delivery to a dedicated CloudWatch log group"
  type        = bool
  default     = false
}

variable "enable_cloudfront_waf" {
  description = "Flag to enable an AWS WAF web ACL on the CloudFront distribution"
  type        = bool
  default     = false
}

variable "waf_monitor_mode" {
  description = "When true, WAF managed rules run in count mode so requests are monitored but not blocked"
  type        = bool
  default     = true
}

variable "sizerestriction_action_override" {
  description = "Override action for the AWSManagedRulesCommonRuleSet size restriction rules. Set to \"count\" to monitor them or \"none\" to use the AWS managed defaults."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "none"], lower(var.sizerestriction_action_override))
    error_message = "sizerestriction_action_override must be one of: count, none."
  }
}

variable "cloudfront_access_log_record_fields" {
  description = "CloudFront standard logging v2 fields to include in delivered access logs"
  type        = list(string)
  default = [
    "date",
    "time",
    "x-edge-location",
    "sc-bytes",
    "c-ip",
    "cs-method",
    "cs(Host)",
    "cs-uri-stem",
    "sc-status",
    "cs(Referer)",
    "cs(User-Agent)",
    "cs-uri-query",
    "cs(Cookie)",
    "x-edge-result-type",
    "x-edge-request-id",
    "x-host-header",
    "cs-protocol",
    "cs-bytes",
    "time-taken",
    "x-forwarded-for",
    "ssl-protocol",
    "ssl-cipher",
    "x-edge-response-result-type",
    "cs-protocol-version",
    "c-port",
    "time-to-first-byte",
    "x-edge-detailed-result-type",
    "sc-content-type",
    "sc-content-len",
    "sc-range-start",
    "sc-range-end",
    "connection-id",
    "asn",
    "c-country",
    "cache-behavior-path-pattern",
  ]
}

variable "enable_sync_external_content" {
  description = "Flag to enable synchronization of external content"
  type        = bool
  default     = true
}

variable "sync_external_content_schedule" {
  description = "The schedule for synchronizing external content"
  type        = string
  default     = "cron(10 9,12,15,18 * * ? *)"
}

variable "db_skip_final_snapshot" {
  description = "Whether to skip the final snapshot when the RDS cluster is deleted. Should be false in production."
  type        = bool
  default     = false
}

variable "db_engine_version" {
  description = "The Aurora PostgreSQL engine version"
  type        = string
  default     = "15.15"
}

variable "db_backup_window" {
  description = "The daily time range (UTC) during which automated backups are created, e.g. '01:00-01:30'"
  type        = string
  default     = "01:00-03:00"
}

variable "db_maintenance_window" {
  description = "The weekly time range (UTC) during which cluster maintenance can occur, e.g. 'sun:02:00-sun:03:00'"
  type        = string
  default     = "sun:03:10-sun:06:00"
}

variable "enable_media_s3" {
  description = "Create an S3 bucket for Wagtail media, serve it through a /media/* CloudFront behaviour (OAC), grant the ECS task role read/write, and set MEDIA_S3_* env vars on the app. Mirrors the app's opt-in: S3 media only activates when MEDIA_S3_BUCKET is set. Requires bootstrap_step >= 1 for the CloudFront wiring."
  type        = bool
  default     = false
}

variable "media_bucket_name" {
  description = "Override the media S3 bucket name (must be globally unique). Empty computes 'wagtail-<wagtail_instance_id>-media-<environment_name>'."
  type        = string
  default     = ""
}

variable "media_s3_location" {
  description = "Key prefix within the media bucket, matching the app's MEDIA_S3_LOCATION. Also drives the CloudFront path pattern (/<media_s3_location>/*)."
  type        = string
  default     = "media"
}

variable "enable_mcp" {
  description = "Run the app's MCP server (manage.py run_mcp_server) as its own ECS service at /mcp on the site's domain, with a WAF rate limit on /mcp and daily tasks that rebuild the content index and fetch external catalogue entries' sources. Sets FEATURE_MCP on every container. Requires bootstrap_step >= 2, and an image with the MCP server."
  type        = bool
  default     = false
}

variable "mcp_task_cpu" {
  description = "CPU units for the MCP server's ECS task, and for the content index's scheduled tasks."
  type        = number
  default     = 256
}

variable "mcp_task_memory" {
  description = "Memory (MiB) for the MCP server's ECS task, and for the content index's scheduled tasks. 1024 leaves room for its 40 concurrent tool calls (about 10 MiB each, on 175 MiB at rest)."
  type        = number
  default     = 1024
}

variable "mcp_desired_count" {
  description = "Number of MCP server tasks to run. Null runs as many as desired_count."
  type        = number
  default     = null
}

variable "mcp_rate_limit" {
  description = "Requests one client IP may make to /mcp in five minutes before the CloudFront WAF refuses it with a 429. Needs enable_cloudfront_waf; the app's own per-process limit is a second line."
  type        = number
  default     = 300

  validation {
    condition     = var.mcp_rate_limit >= 10
    error_message = "mcp_rate_limit must be at least 10, the WAF's minimum."
  }
}

variable "mcp_rate_limit_action" {
  description = "What the WAF does with a client over mcp_rate_limit: block (with a 429), or count only. Independent of waf_monitor_mode, which applies to the managed rule groups."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "count"], var.mcp_rate_limit_action)
    error_message = "mcp_rate_limit_action must be block or count."
  }
}

variable "harvest_external_sources_schedule" {
  description = "When to fetch external catalogue entries' source pages into the content index (EventBridge schedule, UTC). Only with enable_mcp."
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "rebuild_content_index_schedule" {
  description = "When to rebuild the content index, catching changes no publish announces (EventBridge schedule, UTC). Only with enable_mcp."
  type        = string
  default     = "cron(30 6 * * ? *)"
}

variable "enable_ask" {
  description = "Turn on Ask (FEATURE_ASK): the question box block and the /ask/ page, which match questions by meaning with Amazon Titan Text Embeddings V2, and re-rank and summarise the matches with Claude in Amazon Bedrock. The summary is served by the MCP server's service at /ask/summary/, so this needs enable_mcp. Each use of Claude is still switched on in the site's admin (Settings > Ask)."
  type        = bool
  default     = false
}

variable "ask_claude_model" {
  description = "The Claude model Ask calls. On bedrock-runtime, an inference profile: the eu. profile keeps requests in EU regions. On bedrock-mantle, the model ID without a prefix (anthropic.claude-opus-5-5)."
  type        = string
  default     = "eu.anthropic.claude-opus-5-5"
}

variable "ask_claude_endpoint" {
  description = "The Bedrock endpoint Ask calls Claude on: bedrock-runtime (InvokeModel, through an inference profile) or bedrock-mantle (Claude in Amazon Bedrock), where the account and region offer the model there."
  type        = string
  default     = "bedrock-runtime"

  validation {
    condition     = contains(["bedrock-runtime", "bedrock-mantle"], var.ask_claude_endpoint)
    error_message = "ask_claude_endpoint must be bedrock-runtime or bedrock-mantle."
  }
}

variable "ask_daily_token_budget" {
  description = "Tokens Claude may use for Ask in a day (UTC), across every task. Past it, Ask shows its matches without Claude until midnight."
  type        = number
  default     = 2000000

  validation {
    condition     = var.ask_daily_token_budget >= 0
    error_message = "ask_daily_token_budget cannot be negative."
  }
}

variable "bedrock_region" {
  description = "The region Ask calls Amazon Bedrock in, for embeddings and Claude. Null uses the instance's own region."
  type        = string
  default     = null
}
