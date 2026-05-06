terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      environment                    = var.environment
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    file("${path.root}/../../../argocd/install/values.yaml")
  ]

  set {
    name  = "global.env[0].name"
    value = "ENVIRONMENT"
  }

  set {
    name  = "global.env[0].value"
    value = var.environment
  }

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.argocd]
}

# Apply the AppProject and Application manifests after ArgoCD is running
resource "kubernetes_manifest" "argocd_project" {
  manifest = yamldecode(file("${path.root}/../../../argocd/projects/devops-project.yaml"))
  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_app_dev" {
  count    = var.environment == "dev" ? 1 : 0
  manifest = yamldecode(file("${path.root}/../../../argocd/applications/dev.yaml"))
  depends_on = [kubernetes_manifest.argocd_project]
}

resource "kubernetes_manifest" "argocd_app_staging" {
  count    = var.environment == "staging" ? 1 : 0
  manifest = yamldecode(file("${path.root}/../../../argocd/applications/staging.yaml"))
  depends_on = [kubernetes_manifest.argocd_project]
}

resource "kubernetes_manifest" "argocd_app_prod" {
  count    = var.environment == "prod" ? 1 : 0
  manifest = yamldecode(file("${path.root}/../../../argocd/applications/prod.yaml"))
  depends_on = [kubernetes_manifest.argocd_project]
}
