# The MCP server: the app's read-only Model Context Protocol endpoint, which
# lets AI tools search and read the site's published content.
#
# Its own ECS service rather than a second container in the site's task: ECS
# replaces a whole task when any of its target groups fails a health check,
# so a problem here must not restart the site. It runs the same image with the
# same environment, and is reached through the site's own listener at /mcp.
#
# Two daily scheduled tasks keep the content index it reads current. They run
# from this service's task definition, which is smaller than the site's and
# mounts no EFS.

resource "aws_ecs_task_definition" "mcp" {
  count = local.enable_mcp ? 1 : 0

  family                   = local.mcp_task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.mcp_task_cpu
  memory                   = var.mcp_task_memory

  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = local.mcp_task_name
      image = "${var.image}:${var.image_tag}"
      # One worker: each costs about 175 MiB at rest. Add tasks, not workers.
      # Migrations are left to the site's container, which runs them as it starts.
      command = [
        "python", "manage.py", "run_mcp_server",
        "--host", "0.0.0.0", "--port", tostring(local.mcp_port), "--workers", "1",
      ]
      portMappings = [
        {
          containerPort = local.mcp_port
          hostPort      = local.mcp_port
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
          awslogs-stream-prefix = "mcp"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "mcp" {
  count = local.enable_mcp ? 1 : 0

  name            = local.mcp_task_name
  cluster         = data.aws_ecs_cluster.ecs_cluster.arn
  task_definition = aws_ecs_task_definition.mcp[0].arn
  desired_count   = local.mcp_desired_count
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
    target_group_arn = aws_lb_target_group.mcp[0].arn
    container_name   = local.mcp_task_name
    container_port   = local.mcp_port
  }

  # ECS refuses a target group that no listener rule uses yet.
  depends_on = [aws_lb_listener_rule.mcp]
}

resource "aws_lb_target_group" "mcp" {
  count = local.enable_mcp ? 1 : 0

  name        = local.mcp_target_group_name
  port        = local.mcp_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  lifecycle {
    create_before_destroy = false

    precondition {
      condition     = length(local.mcp_target_group_name) <= 32
      error_message = "The MCP target group name (mcp-<wagtail_instance_id>) is over 32 characters."
    }
  }

  health_check {
    # Answers whatever the Host header, so the load balancer can probe by IP,
    # and is open during maintenance and above the rate limit.
    path                = "/mcp/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-299"
  }
}

# Ahead of the site's rule (alb.tf), which catches every path at a later
# priority while this is enabled.
resource "aws_lb_listener_rule" "mcp" {
  count = local.enable_mcp ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp[0].arn
  }

  condition {
    path_pattern {
      values = ["/mcp", "/mcp/*"]
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

# -- the content index's scheduled tasks ----------------------------------------------

locals {
  content_index_tasks = local.enable_mcp ? {
    harvest_external_sources = {
      name        = "harvest-sources"
      description = "Fetch external catalogue entries' source pages into the content index"
      schedule    = var.harvest_external_sources_schedule
    }
    rebuild_content_index = {
      name        = "rebuild-content-index"
      description = "Rebuild the content index the MCP server reads"
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
    task_definition_arn = aws_ecs_task_definition.mcp[0].arn

    network_configuration {
      subnets          = data.aws_subnets.private_subnets.ids
      security_groups  = [aws_security_group.ecs_service.id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = local.mcp_task_name
        command = ["python", "manage.py", each.key]
      }
    ]
  })
}
