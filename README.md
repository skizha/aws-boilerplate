# AWS Infrastructure Boilerplate — AWS Infrastructure Boilerplate

Terraform IaC boilerplate for a travel marketplace platform. Targets a brand-new AWS account. All compute runs on Amazon EKS; supporting services are fully managed AWS.

Architecture spec: [`architecture-design.md`](./architecture-design.md)  
Build progress: [`PROGRESS.md`](./PROGRESS.md)

---

## Stack

| Layer | Technology |
|---|---|
| Compute | Amazon EKS 1.31 — managed node groups + Karpenter |
| Node autoscaling | Karpenter |
| Ingress / load balancing | AWS Load Balancer Controller + ALB |
| Database | RDS PostgreSQL 16 + RDS Proxy |
| Cache | ElastiCache Redis 7.1 |
| Search | Amazon OpenSearch 2.13 |
| Auth | Amazon Cognito |
| Storage / CDN | S3 + CloudFront |
| Real-time | AWS AppSync (WebSocket subscriptions) |
| Background jobs | Lambda + Step Functions + EventBridge |
| Observability | CloudWatch Container Insights + Fluent Bit + X-Ray |
| IaC | Terraform ~> 1.9 |
| CI/CD | GitHub Actions (OIDC — no stored AWS keys) |

---

## Repository layout

```
apps/
  next-web/               # Next.js web app containerized for EKS
infra/
  bootstrap/              # Run once — creates S3 state, DynamoDB lock, GitHub OIDC
  modules/
    networking/           # VPC, subnets, NAT, EKS subnet tags
    eks/                  # EKS cluster, node groups, Karpenter IAM, IRSA per service
    eks-addons/           # Karpenter, AWS LBC, Metrics Server, Fluent Bit (Helm)
    rds/                  # RDS PostgreSQL + RDS Proxy + Secrets Manager
    elasticache/          # Redis replication group
    cognito/              # User pool, hosted UI, web + mobile clients, groups
    storage/              # S3 buckets + CloudFront (web, media, documents)
    opensearch/           # OpenSearch domain in VPC
  environments/
    dev/                  # Single NAT, small instances, single-AZ data layer
    staging/              # Multi-AZ, medium instances
    prod/                 # Full HA, r6g instances, deletion protection enabled
.github/
  workflows/
    terraform.yml         # Plan on PR · dev → staging → prod on merge to main
```

---

## Getting started (brand new AWS account)

**Prerequisites:** AWS CLI, Terraform 1.9+, `kubectl`, `helm`

### Step 1 — Bootstrap (one-time)

```bash
cd infra/bootstrap
terraform init
terraform apply \
  -var="github_org=YOUR_GITHUB_ORG" \
  -var="github_repo=YOUR_REPO_NAME"
```

Note the outputs:
```
tfstate_bucket         = "myapp-tfstate-123456789012"
github_actions_role_arns = {
  dev     = "arn:aws:iam::123456789012:role/myapp-github-actions-dev"
  staging = "arn:aws:iam::..."
  prod    = "arn:aws:iam::..."
}
```

### Step 2 — Wire up remote state

Replace `REPLACE_WITH_BOOTSTRAP_OUTPUT` in each environment's `backend.tf` with the S3 bucket name from Step 1:

```
infra/environments/dev/backend.tf
infra/environments/staging/backend.tf
infra/environments/prod/backend.tf
```

### Step 3 — Configure GitHub

In your GitHub repo settings, create three environments (`dev`, `staging`, `prod`) and add `AWS_ROLE_ARN` as a secret in each, using the role ARNs from Step 1.

Set `prod` to require manual approval before deployment.

### Step 4 — Deploy dev

```bash
cd infra/environments/dev
terraform init
terraform plan
terraform apply
```

Connect to the cluster after apply:
```bash
aws eks update-kubeconfig --name myapp-dev --region us-east-1
kubectl get nodes
```

Build and push the dev web image after the ECR repository is created:

```bash
cd apps/next-web
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker build -t <next_web_ecr_repository_url>:latest .
docker push <next_web_ecr_repository_url>:latest
```

Then re-apply dev, or restart the deployment if Terraform has already created
it before the image was pushed:

```bash
cd infra/environments/dev
terraform apply
kubectl rollout restart deployment/next-web -n myapp
```

---

## Environment sizing

| Resource | dev | staging | prod |
|---|---|---|---|
| NAT Gateways | 1 (shared) | 3 (per AZ) | 3 (per AZ) |
| EKS system nodes | 2 × m5.large | 2 × m5.large | 2 × m5.xlarge |
| Karpenter pool | m5.large/xlarge | m5/m6i large/xlarge | m5/m6i xlarge/2xlarge |
| RDS instance | db.t3.medium | db.t3.medium | db.r6g.large |
| RDS Multi-AZ | No | Yes | Yes |
| Redis nodes | 1 × cache.t3.micro | 2 × cache.t3.small | 3 × cache.r6g.large |
| OpenSearch nodes | 1 × t3.small | 2 × t3.medium | 3 × r6g.large |
| CloudFront price class | 100 (US/EU) | All | All |

---

## CI/CD flow

```
PR opened       → terraform plan on dev (posted as PR comment)
Merge to main   → apply dev → apply staging → [manual approval] → apply prod
```

Authentication uses GitHub OIDC — no AWS keys are stored anywhere. Each environment's role is scoped to its GitHub environment, preventing cross-environment privilege escalation.

---

## Customising

| What to change | Where |
|---|---|
| AWS region | `terraform.tfvars` in each environment |
| Instance sizes | `main.tf` in each environment |
| App service accounts / IRSA | `app_service_accounts` in `eks` module call |
| Cognito callback URLs | `cognito` module call in each environment |
| Karpenter instance types | `karpenter_instance_types` in `eks-addons` module call |
| Helm chart versions | `variables.tf` in `eks-addons` module |
