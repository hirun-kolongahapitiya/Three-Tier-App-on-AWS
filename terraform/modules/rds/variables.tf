variable "name" {
  type        = string
  description = "Name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC the DB lives in"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private data subnet IDs (need at least 2 in different AZs)"
}

variable "app_security_group_id" {
  type        = string
  description = "Security group of the app tier — only this SG can talk to the DB"
}

variable "db_name" {
  type    = string
  default = "todos"
}

variable "db_username" {
  type    = string
  default = "todo_app"
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "multi_az" {
  type        = bool
  default     = false
  description = "Multi-AZ failover. Off in dev for cost, on in prod."
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
