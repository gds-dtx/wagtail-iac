data "aws_vpc" "vpc" {
  id = var.vpc_id
}

# Security Group for ECS tasks
resource "aws_security_group" "ecs_service" {
  name        = "${local.task_name}-sg"
  description = "Allow inbound traffic from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  # The AI service (ai.tf) shares this group, because the database lets it in.
  dynamic "ingress" {
    for_each = local.enable_ai ? [local.ai_port] : []

    content {
      description     = "Allow the AI service HTTP from ALB"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
    }
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      data.aws_vpc.vpc.cidr_block,
    ]
  }

  egress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0",
    ]
  }

  tags = {
    Name = "${local.task_name}-sg"
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}
