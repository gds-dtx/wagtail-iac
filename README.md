# Wagtail IaC Terraform Module

Terraform module for deploying a Wagtail application on ECS Fargate behind CloudFront and ALB, with Aurora PostgreSQL Serverless v2, EFS, CloudWatch logs, Route53 DNS, ACM certificates, and scheduled sync jobs.

## Requirements

- Terraform `~> 1.0`
- Providers:
  - `hashicorp/aws ~> 6.0`
  - `hashicorp/random ~> 3.0`
- Provider aliases expected by this module:
  - `aws` (primary workload account/region)
  - `aws.us-east-1` (CloudFront ACM certificate)
  - `aws.dns-account` (Route53 hosted zone account, can be set the same as `aws`)

## What This Module Creates

- ECS task definition and ECS service for Wagtail
- IAM roles/policies for ECS runtime and scheduled jobs
- EFS access point for `/app/data`
- Aurora PostgreSQL Serverless v2 cluster + instances
- Secrets Manager secrets for DB password and Django secret key
- CloudWatch log group
- Route53 records, ACM certificates, and CloudFront distribution
- Optional AWS WAF web ACL for CloudFront
- Scheduled EventBridge task for `sync_external_content` (optional)

## Prerequisites

- Existing ECS cluster (`cluster_name`)
- Existing VPC with private subnets tagged `Type=private`
- Existing ALB (`alb_arn`) and ALB security group (`alb_security_group_id`)
- Existing EFS filesystem (`efs_id`)
- SSM parameters (required when `bootstrap_step >= 2`):
  - `/wagtail/<environment_name>/<wagtail_instance_id>/oidc_secret`

## Usage

```hcl
module "wagtail_iac" {
  source = "git::ssh://git@github.com/<org>/wagtail-iac.git?ref=<tag>"

  providers = {
    aws             = aws                  # Primary region/account for workload resources
    aws.us-east-1   = aws.us-east-1        # ACM cert for CloudFront must be in us-east-1
    aws.dns-account = aws.dns-account      # Route53 zone and records
  }

  bootstrap_step = 1 # 1: DNS + CloudFront(default cert), 2: ACM + ECS, 3: apex DNS + custom certs

  wagtail_instance_id = "example"               # Instance identifier used in resource names and SSM paths
  wagtail_domain      = "example.gov.uk".       # Public domain for this Wagtail instance
  cluster_name        = "platform-ecs"          # Existing ECS cluster name
  vpc_id              = "vpc-0123456789abcdef0" # Existing VPC ID
  environment_name    = "staging"               # Environment name (e.g. development/staging/production)

  task_memory = 2048 # ECS task memory in MiB
  task_cpu    = 1024 # ECS task CPU units

  efs_id = "fs-0123456789abcdef0" # Existing EFS filesystem ID

  port             = 8000 # Application port used by ALB listener and container
  token_expires_in = 1    # Token expiry in days

  image     = "ghcr.io/govuk-digital-backbone/wagtail-govuk"
  image_tag = "7.3-042"

  log_level = "info" # Application log level

  alb_arn               = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/example/abc123" # Existing ALB ARN
  alb_security_group_id = "sg-0123456789abcdef0" # Existing ALB security group ID

  desired_count = 1 # Number of ECS tasks to run

  wagtail_variables = { # Extra environment variables merged into container environment
    EXAMPLE_FLAG = "true"
  }

  django_settings_module = "govuk.settings.dev" # DJANGO_SETTINGS_MODULE value

  route53_zone_id = "" # Optional: existing hosted zone ID; empty means create zone at bootstrap step 1

  enable_execute_command = false # Enable ECS Exec on service tasks
  enable_cloudfront_waf  = false # Enable AWS WAF on the CloudFront distribution
  waf_monitor_mode       = true  # Count-only mode; set false to enforce managed rule actions

  enable_sync_external_content   = true                          # Enable scheduled sync task
  sync_external_content_schedule = "cron(10 9,12,15,18 * * ? *)" # EventBridge schedule expression

  db_skip_final_snapshot = false                 # Skip final snapshot on delete (use with care)
  db_engine_version      = "15.15"               # Aurora PostgreSQL engine version
  db_backup_window       = "01:00-03:00"         # Daily backup window (UTC)
  db_maintenance_window  = "sun:03:10-sun:06:00" # Weekly maintenance window (UTC)
}
```

## Bootstrap Sequence

1. `bootstrap_step = 1`: creates/uses Route53 zone, creates `alb.<domain>` CNAME, creates CloudFront with default cert.
2. `bootstrap_step = 2`: provisions ACM certs and validation, ECS task/service, IAM execution policy, and optional scheduled task.
3. `bootstrap_step = 3`: enables custom TLS on ALB + CloudFront alias, and creates apex `A`/`AAAA` records for `<domain>`.

## Optional WAF

- `enable_cloudfront_waf`: creates a CloudFront-scope web ACL with AWS managed rule groups and associates it with the distribution.
- `waf_monitor_mode = true`: runs the managed rule groups in `count` mode so you can observe matches before enforcing. Set it to `false` to let the managed rule actions block requests.

## Outputs

- `route53_zone_name_servers`: name servers for the created hosted zone (empty when reusing an existing zone)
- `task_name`: computed ECS task family/service name
- `ssm_name_oidc_secret`: SSM parameter path expected for OIDC client secret
