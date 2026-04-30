# DevOps Project — AWS · EKS · Terraform · Docker · Grafana

End-to-end infrastructure automation: multi-environment AWS infrastructure provisioned with Terraform, containerized app deployed on EKS via Kubernetes, full CI/CD pipeline with GitHub Actions, and observability through Prometheus + Grafana.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    GitHub Actions                    │
│   Terraform Pipeline          Deploy Pipeline        │
│   (plan → apply per env)      (build → dev → stg → prod) │
└──────────────┬───────────────────────┬──────────────┘
               │                       │
               ▼                       ▼
┌──────────────────────┐   ┌────────────────────────────┐
│   AWS Infrastructure  │   │     Amazon ECR             │
│                       │   │     (Docker Images)        │
│  VPC (3-tier subnets) │   └─────────────┬──────────────┘
│  EKS Cluster          │                 │
│  RDS MySQL (Multi-AZ) │                 ▼
│  IAM Roles            │   ┌────────────────────────────┐
│  Security Groups      │   │  Kubernetes (EKS)          │
└──────────────────────┘   │                            │
                            │  App Deployment (HPA)      │
                            │  Ingress (ALB)             │
                            │  Monitoring Namespace      │
                            │    ├── Prometheus          │
                            │    └── Grafana             │
                            └────────────────────────────┘
```

## Repository Structure

```
devops-project/
├── Terraform/
│   ├── modules/
│   │   ├── vpc/               # VPC, subnets, NAT, route tables
│   │   ├── eks/               # EKS cluster, node groups, ECR
│   │   ├── rds/               # RDS MySQL with subnet group
│   │   ├── iam/               # EKS & EC2 IAM roles
│   │   └── security-groups/   # Web, app, and DB security groups
│   └── environments/
│       ├── dev/               # Dev environment (t3.medium nodes)
│       ├── staging/           # Staging environment (t3.large nodes)
│       └── prod/              # Prod environment (t3.xlarge, Multi-AZ RDS)
├── backends/                  # S3 + DynamoDB remote state backend
├── kubernetes/
│   ├── base/                  # Deployment, Service, Ingress, HPA
│   ├── overlays/              # Kustomize patches per environment
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── monitoring/            # Helm values for Prometheus & Grafana
├── docker/
│   ├── Dockerfile             # Multi-stage Python build
│   └── docker-compose.yml     # Local dev stack (app + db + monitoring)
├── App/                       # Flask application
├── monitoring/
│   ├── prometheus/            # Scrape config + alert rules
│   └── grafana/               # Dashboards + provisioning config
└── .github/workflows/
    ├── terraform.yml          # Terraform plan/apply on infra changes
    └── deploy.yml             # Build image → deploy dev → staging → prod
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl
- Helm 3
- Docker

## Quick Start

### 1. Bootstrap Remote State

```bash
cd backends
terraform init
terraform apply -var="bucket_name=your-unique-bucket-name"
```

### 2. Provision Infrastructure

```bash
cd Terraform/environments/dev
terraform init
terraform plan -var="db_password=yourpassword"
terraform apply -var="db_password=yourpassword"
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --name devops-dev --region us-east-1
```

### 4. Deploy Monitoring Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f kubernetes/monitoring/prometheus-values.yaml \
  -f kubernetes/monitoring/grafana-values.yaml
```

### 5. Deploy Application

```bash
kubectl apply -k kubernetes/overlays/dev
```

### 6. Run Locally with Docker Compose

```bash
cd docker
DB_PASSWORD=secret docker-compose up
```

Access: App → http://localhost:5000 | Grafana → http://localhost:3000 | Prometheus → http://localhost:9090

## CI/CD Pipeline

| Trigger | Pipeline |
|---------|----------|
| Push to `main` with changes in `Terraform/` | Terraform plan + apply for all environments |
| Push to `main` with changes in `App/`, `docker/`, `kubernetes/` | Build image → Deploy dev → staging → prod (sequential with approvals) |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_ACCOUNT_ID` | AWS account ID (for ECR URL) |
| `DB_PASSWORD` | RDS master password |

## Environment Differences

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Node type | t3.medium | t3.large | t3.xlarge |
| Node count | 1–3 | 2–5 | 3–10 |
| RDS class | db.t3.micro | db.t3.small | db.r6g.large |
| Multi-AZ RDS | No | No | Yes |
| App replicas | 1 | 2 | 3 |

## Grafana Dashboards

Pre-provisioned dashboards:
- **Application Dashboard** — request rate, p95 latency, CPU, memory, uptime
- **Kubernetes Cluster** — node resource usage (Grafana ID 7249)
- **Node Exporter** — host-level metrics (Grafana ID 1860)
