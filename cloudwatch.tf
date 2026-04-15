resource "aws_cloudwatch_log_group" "wagtail" {
  name              = "/ecs/${local.task_name}"
  retention_in_days = local.wagtail_log_retention_days
  tags = {
    Name = "${local.task_name}-logs"
  }
}

resource "aws_cloudwatch_log_group" "cloudfront_access" {
  count    = local.enable_cloudfront_access_log_delivery ? 1 : 0
  provider = aws.us-east-1

  region = "us-east-1"

  name              = local.cloudfront_access_logs_log_group_name
  retention_in_days = local.cloudfront_log_retention_days
  tags = {
    Name = local.cloudfront_access_logs_log_group_name
  }
}
