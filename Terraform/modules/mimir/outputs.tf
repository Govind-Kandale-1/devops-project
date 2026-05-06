output "mimir_namespace" {
  description = "Namespace where Mimir is installed"
  value       = var.mimir_namespace
}

output "mimir_endpoint" {
  description = "Internal Mimir distributor endpoint for Prometheus remote_write"
  value       = "http://mimir-nginx.${var.mimir_namespace}.svc.cluster.local/api/v1/push"
}

output "mimir_query_endpoint" {
  description = "Internal Mimir query-frontend endpoint for Grafana datasource"
  value       = "http://mimir-nginx.${var.mimir_namespace}.svc.cluster.local/prometheus"
}

output "s3_bucket_name" {
  description = "S3 bucket used for Mimir block storage"
  value       = aws_s3_bucket.mimir.id
}

output "mimir_irsa_role_arn" {
  description = "IAM role ARN for Mimir S3 access (IRSA)"
  value       = aws_iam_role.mimir.arn
}
