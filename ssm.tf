resource "aws_ssm_parameter" "wagtail-oidc-secret" {
  count = var.create_ssm_parameters ? 1 : 0
  name  = local.ssm_oidc_secret
  type  = "SecureString"
  value = "NotSet"
}

data "aws_ssm_parameter" "wagtail-oidc-secret" {
  count = var.bootstrap_step >= 2 ? 1 : 0
  name  = local.ssm_oidc_secret
}
