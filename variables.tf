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
  description = "Gunicorn workers per task (WEB_CONCURRENCY); null means two per vCPU of task_cpu, minimum one."
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

variable "enable_ai" {
  description = "Turns on the AI features (content index, MCP server, AI search) with their own ECS service, scheduled tasks, WAF rate limit and Bedrock access; needs bootstrap_step >= 2 and the account's AWS Marketplace subscription to Claude."
  type        = bool
  default     = false
}

variable "ai_task_cpu" {
  description = "CPU units for the AI service's task and the content index's scheduled tasks."
  type        = number
  default     = 256
}

variable "ai_task_memory" {
  description = "Memory (MiB) for the AI service's task and the content index's scheduled tasks."
  type        = number
  default     = 1024
}

variable "ai_desired_count" {
  description = "Number of AI service tasks; null uses desired_count."
  type        = number
  default     = null
}

variable "ai_rate_limit" {
  description = "Requests per client IP per five minutes to /mcp and /search/ai/* before the CloudFront WAF answers 429; needs enable_cloudfront_waf."
  type        = number
  default     = 300

  validation {
    condition     = var.ai_rate_limit >= 10
    error_message = "ai_rate_limit must be at least 10, the WAF's minimum."
  }
}

variable "ai_rate_limit_action" {
  description = "What the WAF does with a client over ai_rate_limit: block (429) or count; independent of waf_monitor_mode."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "count"], var.ai_rate_limit_action)
    error_message = "ai_rate_limit_action must be block or count."
  }
}

variable "harvest_external_sources_schedule" {
  description = "When to fetch external catalogue entries' sources into the content index (EventBridge schedule, UTC)."
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "rebuild_content_index_schedule" {
  description = "When to rebuild and embed the content index (EventBridge schedule, UTC)."
  type        = string
  default     = "cron(30 6 * * ? *)"
}

variable "ai_claude_model" {
  description = "The Bedrock inference profile AI search calls Claude through; the eu. profile keeps requests in EU regions."
  type        = string
  default     = "eu.anthropic.claude-opus-5-5"
}

variable "ai_daily_token_budget" {
  description = "Tokens Claude may use for AI search per UTC day; past it, AI search shows its matches without Claude."
  type        = number
  default     = 2000000

  validation {
    condition     = var.ai_daily_token_budget >= 0
    error_message = "ai_daily_token_budget cannot be negative."
  }
}

variable "bedrock_region" {
  description = "Region the AI features call Amazon Bedrock in; null uses the instance's own region."
  type        = string
  default     = null
}
