data "aws_ecs_cluster" "ecs_cluster" {
  cluster_name = var.cluster_name
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  count = var.bootstrap_step >= 2 ? 1 : 0

  family                   = local.task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  volume {
    name = "app-data"

    efs_volume_configuration {
      file_system_id     = var.efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.efs_ap_app_data.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = local.task_name
      image = "${var.image}:${var.image_tag}"
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
        }
      ]

      #linuxParameters = {
      #  capabilities = {
      #    add = ["SYS_PTRACE"]
      #  }
      #}

      environment = [
        for k, v in local.wagtail_variables : {
          name  = k
          value = v
        }
      ]

      "secrets" : [
        {
          "name" : "DEFAULT_ADMIN_PASSWORD",
          "valueFrom" : data.aws_ssm_parameter.wagtail-admin-password[0].arn
        },
        {
          "name" : "OIDC_CLIENT_SECRET",
          "valueFrom" : data.aws_ssm_parameter.wagtail-oidc-secret[0].arn
        },
        {
          "name" : "DATABASE_PASSWORD",
          "valueFrom" : aws_secretsmanager_secret.db_password.arn
        },
        {
          "name" : "SECRET_KEY",
          "valueFrom" : aws_secretsmanager_secret.secret_key.arn
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-create-group  = "true" # creates log group if it doesn't exist
          awslogs-group         = aws_cloudwatch_log_group.wagtail.name
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs" # shows up as task_name/<container>/<task-id>
        }
      }

      mountPoints = [
        {
          sourceVolume  = "app-data"
          containerPath = "/app/data"
          readOnly      = false
        }
      ]
    }
    #{
    #  name  = "${local.task_name}-smtp"
    #  image = "ghcr.io/govuk-digital-backbone/govuk-notify-smtp-relay:latest"
    #  portMappings = [
    #    {
    #      containerPort = 2525
    #      hostPort      = 2525
    #    }
    #  ]
    #
    #  logConfiguration = {
    #    logDriver = "awslogs"
    #    options = {
    #      awslogs-create-group  = "true" # creates log group if it doesn't exist
    #      awslogs-group         = aws_cloudwatch_log_group.smtp.name
    #      awslogs-region        = "eu-west-2"
    #      awslogs-stream-prefix = "ecs" # shows up as task_name/<container>/<task-id>
    #    }
    #  }
    #
    #  "secrets" : [
    #    {
    #      "name" : "NOTIFY_API_KEY",
    #      "valueFrom" : data.aws_ssm_parameter.wagtail-notify-api-key[0].arn
    #    },
    #    {
    #      "name" : "NOTIFY_TEMPLATE_ID",
    #      "valueFrom" : data.aws_ssm_parameter.wagtail-notify-template-id[0].arn
    #    }
    #  ]
    #}
  ])
}

resource "aws_ecs_service" "ecs_service" {
  count = var.bootstrap_step >= 2 ? 1 : 0

  name            = local.task_name
  cluster         = data.aws_ecs_cluster.ecs_cluster.arn
  task_definition = aws_ecs_task_definition.ecs_task_definition[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.enable_execute_command
  force_new_deployment   = true

  network_configuration {
    subnets         = data.aws_subnets.private_subnets.ids
    security_groups = [aws_security_group.ecs_service.id]
    # assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    container_name   = local.task_name
    container_port   = 8000
  }
}
