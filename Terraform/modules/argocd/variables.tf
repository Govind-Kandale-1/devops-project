variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "6.7.3"
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}
