data "aws_iam_policy_document" "ecs_events_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_events" {
  count = var.bootstrap_step >= 2 && var.enable_sync_external_content ? 1 : 0

  name               = "${local.task_name}-events-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_events_assume.json
}

resource "aws_iam_role_policy" "ecs_events_run_task" {
  count = var.bootstrap_step >= 2 && var.enable_sync_external_content ? 1 : 0

  name = "${local.task_name}-events-run-task"
  role = aws_iam_role.ecs_events[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = aws_ecs_task_definition.ecs_task_definition[0].arn
        Condition = {
          ArnLike = {
            "ecs:cluster" = data.aws_ecs_cluster.ecs_cluster.arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "sync_external_content" {
  count = var.bootstrap_step >= 2 && var.enable_sync_external_content ? 1 : 0

  name                = "${local.task_name}-sync-external-content"
  description         = "Run sync_external_content management command"
  schedule_expression = var.sync_external_content_schedule
}

resource "aws_cloudwatch_event_target" "sync_external_content" {
  count = var.bootstrap_step >= 2 && var.enable_sync_external_content ? 1 : 0

  rule     = aws_cloudwatch_event_rule.sync_external_content[0].name
  arn      = data.aws_ecs_cluster.ecs_cluster.arn
  role_arn = aws_iam_role.ecs_events[0].arn

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.ecs_task_definition[0].arn

    network_configuration {
      subnets          = data.aws_subnets.private_subnets.ids
      security_groups  = [aws_security_group.ecs_service.id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = local.task_name
        command = ["python", "manage.py", "sync_external_content"]
      }
    ]
  })
}
