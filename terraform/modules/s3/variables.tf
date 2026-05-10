variable "bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name"
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
