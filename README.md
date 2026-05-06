# DevOps Project — AWS · EKS · Terraform · ArgoCD · Docker · Grafana

End-to-end infrastructure automation: multi-environment AWS infrastructure provisioned with Terraform, containerized app deployed on EKS via GitOps with ArgoCD, CI/CD pipeline with GitHub Actions, and observability through Prometheus + Grafana.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       GitHub Actions                         │
│   Terraform Pipeline         Deploy Pipeline                 │
│   (plan → apply per env)     (build → commit tag → sync)    │
└──────────────┬───────────────────────┬──────────────────────┘
               │                       │ image tag commit
               ▼                       ▼
┌──────────────────────┐   ┌────────────────────────────┐
│   AWS Infrastructure  │   │     Amazon ECR             │
│                       │   │     (Docker Images)        │
│  VPC (3-tier subnets) │   └────────────────────────────┘
│  EKS Cluster          │
│  RDS MySQL (Multi-AZ) │   ┌────────────────────────────┐
│  IAM Roles            │   │  ArgoCD (in-cluster)       │
│  Security Groups      │   │                            │
└──────────────────────┘   │  Watches Git repo          │
                            │  Auto-syncs dev            │
                            │  Manual sync staging/prod  │
                            └─────────────┬──────────────┘
                                          │ kubectl apply
                                          ▼
                            ┌────────────────────────────┐
                            │  Kubernetes (EKS)          │
                            │                            │
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
├── argocd/
│   ├── install/               # ArgoCD Helm values
│   ├── projects/              # AppProject (RBAC scoping)
│   └── applications/          # Application manifests (dev/staging/prod)
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

### 5. Bootstrap ArgoCD

ArgoCD is installed by Terraform (runs automatically during `terraform apply`). To access the UI:

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward if not using ingress
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

ArgoCD Applications are applied by Terraform. To manually apply them:

```bash
kubectl apply -f argocd/projects/devops-project.yaml
kubectl apply -f argocd/applications/dev.yaml
kubectl apply -f argocd/applications/staging.yaml
kubectl apply -f argocd/applications/prod.yaml
```

### 6. Deploy Application

Dev syncs automatically once ArgoCD detects a Git change. For staging/prod, use the ArgoCD UI or CLI:

```bash
argocd app sync devops-staging
argocd app sync devops-prod
```

### 7. Run Locally with Docker Compose

```bash
cd docker
DB_PASSWORD=secret docker-compose up
```

Access: App → http://localhost:5000 | Grafana → http://localhost:3000 | Prometheus → http://localhost:9090

## CI/CD Pipeline

| Trigger | Pipeline |
|---------|----------|
| Push to `main` with changes in `Terraform/` | Terraform plan + apply for all environments |
| Push to `main` with changes in `App/`, `docker/`, `kubernetes/` | Build image → commit tag → ArgoCD auto-syncs dev → approval gates for staging/prod |

### GitOps Flow

```
Developer pushes code
    ↓
GitHub Actions builds Docker image → pushes to ECR
    ↓
GitHub Actions commits updated image tag to kubernetes/overlays/*/kustomization.yaml
    ↓
ArgoCD detects Git change
    ├── dev:     auto-syncs immediately (selfHeal + prune enabled)
    ├── staging: waits for manual sync (GitHub Environment approval → argocd app sync)
    └── prod:    waits for manual sync (GitHub Environment approval → argocd app sync)
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_ACCOUNT_ID` | AWS account ID (for ECR URL) |
| `DB_PASSWORD` | RDS master password |
| `ARGOCD_SERVER` | ArgoCD server hostname (e.g. `argocd.example.com`) |
| `ARGOCD_AUTH_TOKEN` | ArgoCD API token for the `deployer` role |

## ArgoCD

| App | Sync Policy | Path |
|-----|-------------|------|
| `devops-dev` | Automatic (prune + selfHeal) | `kubernetes/overlays/dev` |
| `devops-staging` | Manual | `kubernetes/overlays/staging` |
| `devops-prod` | Manual | `kubernetes/overlays/prod` |

All three apps live in the `devops-project` AppProject, which limits source repos and destination namespaces.

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
