output "route53_zone_name_servers" {
  value = try(aws_route53_zone._zone[0].name_servers, [])
}

output "task_name" {
  value = local.task_name
}

output "ssm_name_oidc_secret" {
  value = local.ssm_oidc_secret
}

output "media_bucket_name" {
  description = "Name of the S3 media bucket (empty when enable_media_s3 is false)"
  value       = try(aws_s3_bucket.media[0].bucket, "")
}

output "ai_service_name" {
  description = "Name of the app's ASGI service's ECS service, for the AI features (empty when enable_ai is false)"
  value       = try(aws_ecs_service.ai[0].name, "")
}
