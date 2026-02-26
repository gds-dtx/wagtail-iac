# IAM roles and policies for ECS tasks

## ECS Task Role

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.task_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_efs_file_system" "by_id" {
  file_system_id = var.efs_id
}

resource "aws_iam_role_policy" "efs_mount" {
  name = "${local.task_name}-efs-mount-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = [
          data.aws_efs_file_system.by_id.arn,
          "${data.aws_efs_file_system.by_id.arn}:access-point/*"
        ]
      }
    ]
  })
}

## ECS Task Execution Role

resource "aws_iam_role" "ecs_task_execution" {
  name               = "wagtail-${var.environment_name}-${var.wagtail_instance_id}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume.json
}

data "aws_iam_policy_document" "ecs_execution_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_exec_custom" {
  count = var.bootstrap_step >= 2 ? 1 : 0

  name = "${local.task_name}-exec-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameters"
        ],
        Resource = [
          data.aws_ssm_parameter.wagtail-admin-password[0].arn,
          data.aws_ssm_parameter.wagtail-oidc-secret[0].arn,
          data.aws_ssm_parameter.wagtail-notify-api-key[0].arn,
          data.aws_ssm_parameter.wagtail-notify-template-id[0].arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.secret_key.arn,
        ]
      }
    ]
  })
}
