output "alb_dns_name" {
  description = "Public hostname of the ALB"
  value       = module.alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repo to push images to"
  value       = module.ecs.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true
}

output "rds_secret_arn" {
  value = module.rds.secret_arn
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "alarm_sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "log_group_name" {
  value = module.ecs.log_group_name
}
