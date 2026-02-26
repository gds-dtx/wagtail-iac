resource "random_password" "sql_database_name" {
  length  = 12
  special = false
  upper   = false
  numeric = false

  lifecycle {
    ignore_changes = [
      length,
      special,
      upper,
      numeric,
    ]
  }
}

resource "random_password" "sql_master_username" {
  length  = 8
  special = false
  upper   = false
  numeric = false

  lifecycle {
    ignore_changes = [
      length,
      special,
      upper,
      numeric,
    ]
  }
}

resource "random_password" "sql_master_password" {
  length  = 24
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [
      length,
      special,
      upper,
    ]
  }
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "${local.ssm_key_prefix}/db_password"
  description = "RDS master password for ${local.task_name}"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = local.database_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_kms_key" "db_enc" {
  description             = "${local.task_name} KMS key"
  deletion_window_in_days = 10
}

resource "aws_security_group" "rds_lambda" {
  name        = "${local.task_name}-rds-lambda-inbound"
  description = "Allow RDS inbound traffic from ECS"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    description     = "RDS PostgreSQL"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }

  tags = {
    Name = "${local.task_name}-rds-inbound"
  }
}

resource "aws_rds_cluster_parameter_group" "db" {
  name        = "${local.task_name}-cluster-pg"
  family      = "aurora-postgresql15"
  description = "RDS default cluster parameter group"
}

resource "aws_db_subnet_group" "db" {
  name       = "${local.task_name}-db-subnet-group"
  subnet_ids = data.aws_subnets.private_subnets.ids

  tags = {
    Name = "${local.task_name}-db-subnet-group"
  }
}

resource "aws_rds_cluster" "db" {
  cluster_identifier              = "${local.task_name}-cluster-${random_password.sql_database_name.result}"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = "15.10"
  backup_retention_period         = var.environment_name == "production" ? 14 : 2
  database_name                   = local.database_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.db.name
  master_username                 = local.database_username
  master_password                 = local.database_password
  deletion_protection             = (var.environment_name == "production")
  skip_final_snapshot             = true
  kms_key_id                      = aws_kms_key.db_enc.arn
  storage_encrypted               = true
  db_subnet_group_name            = aws_db_subnet_group.db.name
  vpc_security_group_ids = [
    aws_security_group.rds_lambda.id
  ]

  serverlessv2_scaling_configuration {
    max_capacity = var.environment_name == "production" ? 32.0 : 8.0
    min_capacity = var.environment_name == "production" ? 1.0 : 0.5
  }
}

resource "aws_rds_cluster_instance" "db" {
  count                        = var.environment_name == "production" ? 2 : 1
  cluster_identifier           = aws_rds_cluster.db.id
  instance_class               = "db.serverless"
  engine                       = aws_rds_cluster.db.engine
  engine_version               = aws_rds_cluster.db.engine_version
  performance_insights_enabled = var.environment_name == "production" ? true : false
}
