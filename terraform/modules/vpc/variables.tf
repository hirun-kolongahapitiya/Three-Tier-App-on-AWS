variable "name" {
  description = "Prefix used for naming/tagging VPC resources"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread subnets across (2 minimum for RDS Multi-AZ)"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway shared across AZs (cheaper, lower HA). Set to false for prod."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
