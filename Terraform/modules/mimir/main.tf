terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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

# ── S3 bucket for block storage ──────────────────────────────────────────────

resource "aws_s3_bucket" "mimir" {
  bucket        = var.s3_bucket_name
  force_destroy = var.environment != "prod"

  tags = {
    Name        = var.s3_bucket_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mimir" {
  bucket                  = aws_s3_bucket.mimir.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "mimir" {
  bucket = aws_s3_bucket.mimir.id

  rule {
    id     = "expire-old-chunks"
    status = "Enabled"
    filter { prefix = "" }

    expiration {
      days = var.environment == "prod" ? 90 : 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ── IRSA — IAM role for Mimir pods to access S3 ──────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "mimir_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.eks_oidc_provider}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.mimir_namespace}:mimir"]
    }
  }
}

data "aws_iam_policy_document" "mimir_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.mimir.arn,
      "${aws_s3_bucket.mimir.arn}/*",
    ]
  }
}

resource "aws_iam_role" "mimir" {
  name               = "mimir-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.mimir_assume_role.json

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "mimir_s3" {
  name   = "mimir-s3-${var.environment}"
  role   = aws_iam_role.mimir.id
  policy = data.aws_iam_policy_document.mimir_s3.json
}

# ── Per-tenant runtime overrides ConfigMap ────────────────────────────────────

resource "kubernetes_config_map" "mimir_tenant_overrides" {
  metadata {
    name      = "mimir-tenant-overrides"
    namespace = var.mimir_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "overrides.yaml" = yamlencode({
      overrides = {
        for tenant in var.tenants : tenant => {
          ingestion_rate        = tenant == "prod" ? 100000 : 50000
          ingestion_burst_size  = tenant == "prod" ? 200000 : 100000
          max_global_series_per_user = tenant == "prod" ? 2000000 : 500000
          ruler_max_rules_per_rule_group = 20
          ruler_max_rule_groups_per_tenant = 10
        }
      }
    })
  }
}

# ── Tenant ID ConfigMap — consumed by Prometheus remoteWrite env var ─────────

resource "kubernetes_config_map" "mimir_tenant_id" {
  metadata {
    name      = "mimir-tenant-id"
    namespace = var.mimir_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    tenant_id = var.environment
  }
}

# ── Mimir Helm release ────────────────────────────────────────────────────────

resource "helm_release" "mimir" {
  name       = "mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = var.mimir_chart_version
  namespace  = var.mimir_namespace

  values = [
    templatefile("${path.module}/../../kubernetes/monitoring/mimir-values.yaml", {
      s3_bucket_name  = var.s3_bucket_name
      aws_region      = var.aws_region
      irsa_role_arn   = aws_iam_role.mimir.arn
      replicas        = var.mimir_replicas
      storage_size    = var.storage_size
      environment     = var.environment
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [
    aws_s3_bucket.mimir,
    kubernetes_config_map.mimir_tenant_overrides,
  ]
}
