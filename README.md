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
- Optional MCP server: its own ECS service at `/mcp`, a WAF rate limit, and scheduled tasks that keep its content index current
- Optional Ask: the `/ask/` page, matching by meaning with Titan embeddings, and re-ranking and a summary with Claude in Amazon Bedrock

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

  web_concurrency = null # Gunicorn workers per task; null means two per vCPU (task_cpu / 512), minimum one

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

  enable_mcp            = false   # Run the app's MCP server at /mcp, with its scheduled tasks
  mcp_task_cpu          = 256     # MCP server task CPU units (also its scheduled tasks)
  mcp_task_memory       = 1024    # MCP server task memory in MiB
  mcp_desired_count     = null    # MCP server tasks; null means desired_count
  mcp_rate_limit        = 300     # Requests per client IP per 5 minutes on /mcp (needs enable_cloudfront_waf)
  mcp_rate_limit_action = "block" # block (with a 429) or count

  harvest_external_sources_schedule = "cron(0 6 * * ? *)"  # Fetch external entries' sources (UTC)
  rebuild_content_index_schedule    = "cron(30 6 * * ? *)" # Rebuild the content index (UTC)
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

## Optional MCP server

Set `enable_mcp = true` to run the app's MCP server, which lets AI tools search
and read the site's published content. It needs `bootstrap_step >= 2` and an
image that has it (`manage.py run_mcp_server`).

What it creates:

- **An ECS service**, `wagtail-<instance_id>-mcp`.
  - **What it runs:** the same image and environment as the site, with
    `python manage.py run_mcp_server --host 0.0.0.0 --port 8001 --workers 1`
    on `mcp_task_cpu` and `mcp_task_memory` (256 / 1024 by default).
  - **Why it is separate:** ECS replaces a whole task when one of its target
    groups fails a health check, so the MCP server must not share the site's
    task.
  - **What it does not do:** it mounts no EFS and runs no migrations; the
    site's container still runs them.
  - **Networking:** it shares the site's security group, which the database
    lets in. That group also lets port 8001 in from the load balancer.
- **A target group** (`mcp-<instance_id>`) with a health check of
  `GET /mcp/health`.
- **A listener rule** at priority 10 sending `/mcp` and `/mcp/*` to it, with
  the same host and `X-ALB-Protection` conditions as the site's rule. The
  site's rule moves from priority 1 to 20 so that it comes after; instances
  without the MCP server keep priority 1. Check the plan: if Terraform replaces
  the site's rule rather than updating it, the site answers 404 for a moment
  during the apply.
- **Environment variables** on every container:
  - `FEATURE_MCP=true`: the site writes the content index as editors publish,
    and the MCP server will not start without it.
  - `MCP_CLIENT_IP_HEADER=true-client-ip`, from `bootstrap_step = 3`, so the
    app's rate limit counts each viewer rather than CloudFront's edges. The
    viewer request function sets that header from the viewer's own address.
    Before step 3 there is no function to overwrite it, so it is not trusted.
- **A WAF rate limit** of `mcp_rate_limit` requests per client IP per five
  minutes on URIs starting `/mcp`, answered with a 429, when
  `enable_cloudfront_waf` is on. Its action (`mcp_rate_limit_action`) is its
  own: `waf_monitor_mode` applies to the managed rule groups only.
- **Two scheduled tasks**, run like `sync_external_content` but from the MCP
  server's smaller task definition:
  - `harvest_external_sources` (`harvest_external_sources_schedule`, 06:00
    UTC daily): fetches external catalogue entries' source pages into the
    index. It needs outbound https to the sources, which the tasks' subnets
    already give `sync_external_content`.
  - `rebuild_content_index` (`rebuild_content_index_schedule`, 06:30 UTC
    daily): rebuilds the index, catching changes that no publish announces.

After the first apply, fill the index once with ECS Exec on a site or MCP
task:

```bash
python manage.py rebuild_content_index
python manage.py harvest_external_sources
```

## Optional Ask

Set `enable_ask = true` (with `enable_mcp`) to turn on Ask: the question box
block and the `/ask/` page it posts to, which shows the content index's
closest matches to a question as catalogue cards. It needs an image that has
it (`FEATURE_ASK`).

What it adds:

- **Environment variables** on every container: `FEATURE_ASK=true`,
  `CONTENT_INDEX_EMBEDDINGS=bedrock`, `ASK_CLAUDE=bedrock`,
  `ASK_CLAUDE_MODEL` (`ask_claude_model`), `ASK_DAILY_TOKEN_BUDGET`
  (`ask_daily_token_budget`, 2 million by default) and the Bedrock region
  (`bedrock_region`, the instance's own by default).
- **A task role policy** allowing:
  - `bedrock:InvokeModel` on Amazon Titan Text Embeddings V2, which embeds
    the content index (in the nightly `rebuild_content_index`) and each
    question;
  - `bedrock-mantle:CreateInference`, for Claude in Amazon Bedrock. Its
    resource is `*` until the model's ARN form on that endpoint is confirmed.
- **`/ask/summary/` on the MCP listener rule**, so the summary goes to the
  MCP service (uvicorn) rather than the site's gunicorn.

Before turning it on:

- **Model access:** in the Bedrock console, check that the account can use
  Titan Text Embeddings V2 and the Claude model in `bedrock_region`. Some
  Claude models need a one-time access request.
- **Where Claude runs:** Claude in Amazon Bedrock offers global and
  geographic (EU) routing from `eu-west-2`. Confirm which one the model ID
  routes to before questions from the public go through it.

After the first apply:

- **Embed the index:** run `python manage.py rebuild_content_index` once,
  with ECS Exec or a one-off task. The nightly run keeps it current after
  that.
- **Switch Claude on:** in the site's admin, under **Settings > Ask**, turn on
  re-ranking and the summary. Both are off until then, and either can be
  turned off there at any time.

## Outputs

- `route53_zone_name_servers`: name servers for the created hosted zone (empty when reusing an existing zone)
- `task_name`: computed ECS task family/service name
- `ssm_name_oidc_secret`: SSM parameter path expected for OIDC client secret
- `media_bucket_name`: name of the S3 media bucket (empty when `enable_media_s3` is false)
- `mcp_service_name`: name of the MCP server's ECS service (empty when `enable_mcp` is false)
