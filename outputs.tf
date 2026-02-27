output "route53_zone_name_servers" {
  value = try(aws_route53_zone._zone[0].name_servers, [])
}

output "task_name" {
  value = local.task_name
}

output "ssm_name_oidc_secret" {
  value = local.ssm_oidc_secret
}
