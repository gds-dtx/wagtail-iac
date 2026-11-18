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

resource "aws_iam_role_policy" "media_s3" {
  count = local.enable_media_s3 ? 1 : 0

  name = "${local.task_name}-media-s3-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.media[0].arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.media[0].arn}/*"]
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
          data.aws_ssm_parameter.wagtail-oidc-secret[0].arn
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

# The AI features: Titan Text Embeddings V2 (bedrock-runtime) for the content
# index and each AI search question, and Claude to re-rank and summarise. On
# the task role, which the site, the app's ASGI service and the scheduled tasks
# all use.
#
# Claude goes through an inference profile (eu. by default), which needs
# InvokeModel on the profile and on the model in each region the profile
# routes to; the second is only allowed through that profile.
data "aws_caller_identity" "current" {}

locals {
  ai_inference_profile_arn = "arn:aws:bedrock:${local.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.ai_claude_model}"
}

data "aws_iam_policy_document" "ai_bedrock" {
  statement {
    sid       = "TitanEmbeddings"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${local.bedrock_region}::foundation-model/amazon.titan-embed-text-v2:0"]
  }

  statement {
    sid       = "ClaudeInferenceProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.ai_inference_profile_arn]
  }

  statement {
    sid       = "ClaudeThroughTheProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:*::foundation-model/${local.ai_claude_foundation_model}"]
    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [local.ai_inference_profile_arn]
    }
  }
}

resource "aws_iam_role_policy" "ai_bedrock" {
  count = local.enable_ai ? 1 : 0

  name   = "${local.task_name}-ai-bedrock-policy"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ai_bedrock.json
}
