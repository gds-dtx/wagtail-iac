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
- Optional S3 media bucket served via a `/media/*` CloudFront behaviour (OAC)
- Scheduled EventBridge task for `sync_external_content` (optional)
- Optional AI features: the MCP server and AI search as their own ECS service, with Bedrock access, a WAF rate limit and content index tasks

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

  web_concurrency = null # Gunicorn workers per task; null means two per vCPU, minimum one

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

  django_settings_module = "govuk.settings.production" # DJANGO_SETTINGS_MODULE value

  route53_zone_id    = ""   # Optional: existing hosted zone ID; empty means create zone at bootstrap step 1
  enable_caa_records = true # Publish Amazon CAA records when ACM certificates are enabled

  enable_execute_command = false # Enable ECS Exec on service tasks
  enable_cloudfront_waf  = false # Enable AWS WAF on the CloudFront distribution
  waf_monitor_mode       = true  # Count-only mode; set false to enforce managed rule actions

  enable_sync_external_content   = true                          # Enable scheduled sync task
  sync_external_content_schedule = "cron(10 9,12,15,18 * * ? *)" # EventBridge schedule expression

  db_skip_final_snapshot = false                 # Skip final snapshot on delete (use with care)
  db_engine_version      = "15.15"               # Aurora PostgreSQL engine version
  db_backup_window       = "01:00-03:00"         # Daily backup window (UTC)
  db_maintenance_window  = "sun:03:10-sun:06:00" # Weekly maintenance window (UTC)

  enable_media_s3   = false # Create S3 media bucket + /media/* CloudFront behaviour and wire the app to it
  media_bucket_name = ""    # Optional override; empty computes wagtail-<instance_id>-media-<environment_name>
  media_s3_location = "media" # Key prefix and CloudFront path pattern (/media/*)

  enable_ai             = false   # MCP server and AI search (see Optional AI features)
  ai_task_cpu           = 256     # AI service task CPU units (also its scheduled tasks)
  ai_task_memory        = 1024    # AI service task memory in MiB
  ai_desired_count      = null    # AI service tasks; null means desired_count
  ai_rate_limit         = 300     # Requests per client IP per 5 minutes (needs enable_cloudfront_waf)
  ai_rate_limit_action  = "block" # block (with a 429) or count
  ai_claude_model       = "eu.anthropic.claude-opus-5-5" # Bedrock inference profile
  ai_daily_token_budget = 2000000 # Tokens Claude may use for AI search a day
  bedrock_region        = null    # null means the instance's own region

  harvest_external_sources_schedule = "cron(0 6 * * ? *)"  # UTC
  rebuild_content_index_schedule    = "cron(30 6 * * ? *)" # UTC
}
```

## Bootstrap Sequence

1. `bootstrap_step = 1`: creates/uses Route53 zone, creates `alb.<domain>` CNAME, creates CloudFront with default cert.
2. `bootstrap_step = 2`: publishes CAA records (enabled by default), provisions ACM certs and their Route53 DNS validation records, ECS task/service, IAM execution policy, and optional scheduled task.
3. `bootstrap_step = 3`: enables custom TLS on ALB + CloudFront alias, and creates apex `A`/`AAAA` records for `<domain>`.

## CAA Records

`enable_caa_records` defaults to `true`. When `bootstrap_step >= 2`, the module creates CAA record sets for both `wagtail_domain` and `www.<wagtail_domain>` in the selected Route53 hosted zone using `aws.dns-account`. Each record set authorizes `amazon.com`, `amazontrust.com`, `awstrust.com`, and `amazonaws.com`, as described in the [ACM CAA documentation](https://docs.aws.amazon.com/acm/latest/userguide/setup.html#setup-caa). Both ACM certificate requests wait for these record sets to be created.

Set `enable_caa_records = false` if CAA records are managed elsewhere. ACM certificates and their Route53 DNS validation records are still created. Existing CAA record sets are not overwritten automatically; import those record sets into this module or disable CAA management.

## Optional S3 Media

Set `enable_media_s3 = true` to store Wagtail media (uploaded images and, via the
same default storage, `wagtail.documents`) on S3 instead of the per-task EFS/container
path. This mirrors the app's opt-in behaviour: the Wagtail settings switch to
`S3Storage` only when `MEDIA_S3_BUCKET` is set, which this module sets on the ECS task
when the flag is on.

What it creates:

- **S3 bucket** (`media_bucket_name`, default `wagtail-<instance_id>-media-<environment_name>`)
  with versioning on, SSE (AES256), `BucketOwnerEnforced` ownership, and all public
  access blocked. A bucket policy denies non-TLS access and allows read only from this
  distribution via Origin Access Control.
- **`/media/*` cache behaviour** on the existing CloudFront distribution, pointing at the
  S3 origin (cached, `Managed-CachingOptimized`). Media is served from the site's own
  domain, e.g. `https://<wagtail_domain>/media/...`.
- **IAM policy** on the ECS task role granting `s3:GetObject`/`PutObject`/`DeleteObject`
  on objects and `s3:ListBucket` on the bucket. Credentials come from the task role — no
  access keys.
- **Env vars** on the task: `MEDIA_S3_BUCKET`, `MEDIA_S3_REGION`, `MEDIA_S3_LOCATION`, and
  `MEDIA_S3_CUSTOM_DOMAIN` (= `wagtail_domain`, since media is same-origin).

Notes:

- Requires `bootstrap_step >= 1` (the CloudFront distribution must exist). Because
  `MEDIA_S3_CUSTOM_DOMAIN` is the site domain, enable this once the site serves on its
  custom domain (`bootstrap_step = 3`), otherwise media URLs resolve only after the alias
  is live.
- Because media serves from the same origin, **no CSP `img-src` change is needed** — the
  app's `'self'` already covers it. (A separate `media.<domain>` distribution would have
  required one.)
- Objects are private and served publicly through CloudFront (OAC); the app keeps
  `MEDIA_S3_QUERYSTRING_AUTH` off. Documents share the default storage, so they go to S3 too.


## Optional WAF

- `enable_cloudfront_waf`: creates a CloudFront-scope web ACL with AWS managed rule groups and associates it with the distribution.
- `waf_monitor_mode = true`: runs the managed rule groups in `count` mode so you can observe matches before enforcing. Set it to `false` to let the managed rule actions block requests.

## Optional AI features

Set `enable_ai = true` to turn on the app's AI features (`FEATURE_AI`): the
content index, the MCP server and AI search. It needs `bootstrap_step >= 2`
and an image with `manage.py run_service`.

What it creates:

- **An ECS service**, `wagtail-<instance_id>-ai`, running the app's ASGI
  service from the site's image and environment on port 8001. It serves `/mcp`
  and `/search/ai/*`, so the site's gunicorn workers never wait on Claude. It
  mounts no EFS and runs no migrations.
- **A target group** (`ai-<instance_id>`, health check `GET /service/health`)
  and **a listener rule** at priority 11 for those paths. The site's rule
  moves from priority 1 to 20. Check the plan: if Terraform replaces the site's
  rule rather than updating it, the site returns 404 briefly during the apply.
- **Environment variables** on every container: `FEATURE_AI`,
  `CONTENT_INDEX_EMBEDDINGS`, `AI_CLAUDE`, `AI_CLAUDE_MODEL`,
  `AI_DAILY_TOKEN_BUDGET` and the Bedrock region, plus
  `CLIENT_IP_HEADER=true-client-ip` from `bootstrap_step = 3`.
- **A task role policy** allowing `bedrock:InvokeModel` on Titan Text
  Embeddings V2 and on the Claude inference profile in `ai_claude_model`.
- **A WAF rate limit** of `ai_rate_limit` requests per client IP per five
  minutes on those paths, when `enable_cloudfront_waf` is on. Set its action
  with `ai_rate_limit_action`; `waf_monitor_mode` does not affect it.
- **Two daily scheduled tasks**: `harvest_external_sources` (06:00 UTC) and
  `rebuild_content_index` (06:30 UTC).

Before turning it on:

- In the Bedrock console, check that the account can use Titan Text
  Embeddings V2 and the Claude model in `bedrock_region`.
- Once per account, subscribe to the Claude model in AWS Marketplace (from
  Bedrock's model catalogue) with a role allowed `aws-marketplace:Subscribe`.
- The default `eu.` inference profile keeps requests in EU regions; a
  `global.` profile routes them worldwide.

After the first apply:

- With ECS Exec on a site or AI service task, run
  `python manage.py rebuild_content_index`, then
  `python manage.py harvest_external_sources`. The nightly tasks keep the
  index current after that.
- In the site's admin, under **Settings > Search**, choose AI search and turn
  on re-ranking and the summary. Claude is not called until then.

## Outputs

- `route53_zone_name_servers`: name servers for the created hosted zone (empty when reusing an existing zone)
- `task_name`: computed ECS task family/service name
- `ssm_name_oidc_secret`: SSM parameter path expected for OIDC client secret
- `media_bucket_name`: name of the S3 media bucket (empty when `enable_media_s3` is false)
- `ai_service_name`: name of the app's ASGI service's ECS service (empty when `enable_ai` is false)
