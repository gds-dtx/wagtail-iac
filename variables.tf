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
  default     = "govuk.settings.dev"
}

variable "route53_zone_id" {
  description = "The ID of the Route53 hosted zone"
  type        = string
  default     = ""
}

variable "create_ssm_parameters" {
  description = "Flag to enable creation of SSM parameters"
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Flag to enable ECS execute command feature"
  type        = bool
  default     = false
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
  default     = "15.10"
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
