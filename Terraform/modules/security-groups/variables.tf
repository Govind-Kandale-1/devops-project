variable "vpc_id" {
  description = "VPC ID to attach security groups to"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
