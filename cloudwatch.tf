resource "aws_cloudwatch_log_group" "wagtail" {
  name              = "/ecs/${local.task_name}"
  retention_in_days = local.log_retention_days
  tags = {
    Name = "${local.task_name}-logs"
  }
}
