variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name — used to scope IAM role names"
  type        = string
  default     = "eks-cluster"
}
