variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "mimir_chart_version" {
  description = "Grafana Mimir Helm chart version"
  type        = string
  default     = "5.3.0"
}

variable "mimir_namespace" {
  description = "Kubernetes namespace for Mimir"
  type        = string
  default     = "monitoring"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Mimir block storage. Must be globally unique."
  type        = string
}

variable "mimir_replicas" {
  description = "Number of Mimir single-binary replicas"
  type        = number
  default     = 1
}

variable "storage_size" {
  description = "PVC size for Mimir WAL (write-ahead log)"
  type        = string
  default     = "20Gi"
}

variable "tenants" {
  description = "List of tenant IDs for which limits are pre-configured"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "eks_oidc_provider" {
  description = "EKS OIDC provider URL (without https://) for IRSA trust policy"
  type        = string
}
