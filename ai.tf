# The app's async ASGI service makes the slow Claude calls, so they never tie up gunicorn.
# A separate ECS service: a failing health check here must not replace the site's task.
# Two daily scheduled tasks keep the content index current and embedded.

resource "aws_ecs_task_definition" "ai" {
  count = local.enable_ai ? 1 : 0

  family                   = local.ai_task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ai_task_cpu
  memory                   = var.ai_task_memory

  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = local.ai_task_name
      image = "${var.image}:${var.image_tag}"
      # One worker (about 175 MiB each): add tasks, not workers. The site runs migrations.
      command = [
        "python", "manage.py", "run_service",
        "--host", "0.0.0.0", "--port", tostring(local.ai_port), "--workers", "1",
      ]
      portMappings = [
        {
          containerPort = local.ai_port
          hostPort      = local.ai_port
        }
      ]

      environment = [
        for k, v in local.wagtail_variables : {
          name  = k
          value = v
        }
      ]

      "secrets" : [
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
          awslogs-create-group  = "true"
          awslogs-group         = aws_cloudwatch_log_group.wagtail.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ai"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ai" {
  count = local.enable_ai ? 1 : 0

  name            = local.ai_task_name
  cluster         = data.aws_ecs_cluster.ecs_cluster.arn
  task_definition = aws_ecs_task_definition.ai[0].arn
  desired_count   = local.ai_desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.enable_execute_command
  force_new_deployment   = true

  # Django starts in about 15 seconds on a quarter of a vCPU.
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets = data.aws_subnets.private_subnets.ids
    # The site's group: the database only lets that one in.
    security_groups = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ai[0].arn
    container_name   = local.ai_task_name
    container_port   = local.ai_port
  }

  # ECS refuses a target group that no listener rule uses yet.
  depends_on = [aws_lb_listener_rule.ai]
}

resource "aws_lb_target_group" "ai" {
  count = local.enable_ai ? 1 : 0

  name        = local.ai_target_group_name
  port        = local.ai_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = false

    precondition {
      condition     = length(local.ai_target_group_name) <= 32
      error_message = "The AI service's target group name (ai-<wagtail_instance_id>) is over 32 characters."
    }
  }

  health_check {
    # Ignores the Host header, maintenance and rate limits, so the ALB can probe by IP.
    path                = "/service/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-299"
  }
}

# Must come before the site's catch-all rule (alb.tf). Not 10: an instance moving
# from enable_mcp may still hold the old /mcp rule there while this is created.
resource "aws_lb_listener_rule" "ai" {
  count = local.enable_ai ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ai[0].arn
  }

  condition {
    path_pattern {
      values = local.ai_service_paths
    }
  }

  condition {
    host_header {
      values = [var.wagtail_domain]
    }
  }

  condition {
    http_header {
      http_header_name = "X-ALB-Protection"
      values           = [random_password.cloudfront_origin_header.result]
    }
  }

  lifecycle {
    create_before_destroy = false
  }
}

locals {
  content_index_tasks = local.enable_ai ? {
    harvest_external_sources = {
      name        = "harvest-sources"
      description = "Fetch external catalogue entries' source pages into the content index"
      schedule    = var.harvest_external_sources_schedule
    }
    rebuild_content_index = {
      name        = "rebuild-content-index"
      description = "Rebuild and embed the content index the AI features read"
      schedule    = var.rebuild_content_index_schedule
    }
  } : {}
}

resource "aws_cloudwatch_event_rule" "content_index" {
  for_each = local.content_index_tasks

  name                = "${local.task_name}-${each.value.name}"
  description         = each.value.description
  schedule_expression = each.value.schedule
}

resource "aws_cloudwatch_event_target" "content_index" {
  for_each = local.content_index_tasks

  rule     = aws_cloudwatch_event_rule.content_index[each.key].name
  arn      = data.aws_ecs_cluster.ecs_cluster.arn
  role_arn = aws_iam_role.ecs_events[0].arn

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.ai[0].arn

    network_configuration {
      subnets          = data.aws_subnets.private_subnets.ids
      security_groups  = [aws_security_group.ecs_service.id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = local.ai_task_name
        command = ["python", "manage.py", each.key]
      }
    ]
  })
}
