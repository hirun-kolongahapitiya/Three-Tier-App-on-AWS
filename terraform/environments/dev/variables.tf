variable "project" {
  type        = string
  default     = "todoapp"
  description = "Project name, used as prefix for all resources"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Initial image tag — overridden by GitHub Actions on subsequent deploys"
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM cert ARN for HTTPS. Leave empty to serve HTTP only."
}

variable "alert_emails" {
  type        = list(string)
  default     = []
  description = "Email addresses subscribed to the SNS alarm topic"
}
