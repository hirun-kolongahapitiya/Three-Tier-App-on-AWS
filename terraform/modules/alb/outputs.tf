output "dns_name" {
  value = aws_lb.this.dns_name
}

output "zone_id" {
  value = aws_lb.this.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "Used in CloudWatch alarm dimensions"
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Used in CloudWatch alarm dimensions"
  value       = aws_lb_target_group.app.arn_suffix
}

output "security_group_id" {
  value = aws_security_group.alb.id
}
