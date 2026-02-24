locals {
  task_name          = "wagtail-${var.wagtail_instance_id}"

  ssm_key_prefix         = "/wagtail/${var.environment_name}/${var.wagtail_instance_id}"
  ssm_admin_password     = "${local.ssm_key_prefix}/admin_password"
  ssm_oidc_secret        = "${local.ssm_key_prefix}/oidc_secret"
  ssm_notify_api_key     = "/wagtail/${var.environment_name}/notify_api_key"
  ssm_notify_template_id = "/wagtail/${var.environment_name}/notify_template_id"

  log_retention_days = var.environment_name == "production" ? 365 : 14

  database_username = sensitive(random_password.sql_master_username.result)
  database_password = sensitive(random_password.sql_master_password.result)
  database_name     = sensitive("db${random_password.sql_database_name.result}")
  connection_string = sensitive("postgresql://${local.database_username}:${local.database_password}@${aws_rds_cluster.db.endpoint}/${local.database_name}")

  wagtail_variables = merge(
    var.wagtail_variables,
    {
      DOMAIN                       = var.wagtail_domain
      BASE_URL                     = "https://${var.wagtail_domain}"
      DATABASE_NAME                = local.database_name
      DATABASE_USER                = local.database_username
      DATABASE_PASSWORD            = local.database_password
      DATABASE_HOST                = aws_rds_cluster.db.endpoint
      SECRET_KEY                   = random_password.wagtail-secret-key.result
      LOG_LEVEL                    = var.log_level
      TRUST_PROXY                  = "true"
      TOKEN_EXPIRES_IN             = tostring(var.token_expires_in)
      DEFAULT_LANGUAGE             = "en-GB"
      SMTP_HOST                    = "127.0.0.1"
      SMTP_PORT                    = "2525"
      SMTP_SECURE                  = "false"
      SMTP_TLS_REJECT_UNAUTHORIZED = "false"
      DJANGO_SETTINGS_MODULE       = var.django_settings_module
    }
  )
}

resource "random_password" "wagtail-secret-key" {
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
