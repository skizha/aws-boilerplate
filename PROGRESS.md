# GetMyTrip — Build Progress

**Last updated:** 2026-04-24  
**Active branch:** main

---

## What this project is

Terraform IaC boilerplate for GetMyTrip — a travel marketplace platform (travelers post requests, agencies bid). Targets AWS, EKS-based compute, fully managed supporting services. Architecture spec is in [`getmytrip-architecture-design.md`](./getmytrip-architecture-design.md).

---

## Completed

### Architecture Design (v2.0)
- [x] Full architecture document written — `getmytrip-architecture-design.md`
- [x] Migrated compute from AWS App Runner → Amazon EKS (v2.0 update)
- [x] EKS architecture decisions documented: Karpenter, AWS LBC, IRSA, HPA, Fluent Bit

### Terraform Boilerplate — `infra/`

#### Bootstrap (run once on a brand new AWS account)
- [x] S3 remote state bucket with versioning + encryption
- [x] DynamoDB state lock table
- [x] GitHub Actions OIDC provider
- [x] IAM roles for GitHub Actions — one per environment (dev/staging/prod), locked to repo+env

#### Module: `networking`
- [x] VPC via `terraform-aws-modules/vpc`
- [x] 3 public subnets + 3 private subnets across 3 AZs
- [x] NAT Gateway (single in dev, one-per-AZ in staging/prod)
- [x] Subnet tags for EKS auto-discovery (ALB controller + Karpenter)

#### Module: `eks`
- [x] EKS managed cluster (v1.31) via `terraform-aws-modules/eks`
- [x] System managed node group (on-demand, 2 nodes min, tainted for critical addons)
- [x] EKS managed add-ons: `coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`
- [x] Karpenter IAM resources (instance profile, IRSA role, SQS interruption queue)
- [x] IRSA for EBS CSI driver
- [x] IRSA for AWS Load Balancer Controller
- [x] IRSA per application service account (one role per service)

#### Module: `eks-addons`
- [x] Karpenter Helm release + `EC2NodeClass` + `NodePool` manifests
- [x] AWS Load Balancer Controller Helm release
- [x] Metrics Server (required for HPA)
- [x] Fluent Bit → CloudWatch Container Insights
- [x] Application Kubernetes namespace

#### Module: `rds`
- [x] RDS PostgreSQL 16 via `terraform-aws-modules/rds`
- [x] Multi-AZ toggle (off in dev, on in staging/prod)
- [x] Performance Insights + CloudWatch log export
- [x] RDS Proxy (connection pooling for EKS horizontal scaling)
- [x] Credentials auto-generated and stored in Secrets Manager

#### Module: `elasticache`
- [x] Redis 7.1 replication group
- [x] Encryption at rest + in transit
- [x] Auto-failover when `num_cache_clusters > 1`
- [x] Snapshot retention per environment

#### Module: `cognito`
- [x] Cognito User Pool (email auth, custom `role` attribute)
- [x] Hosted UI domain
- [x] Web client + mobile client (separate, correct auth flows)
- [x] User groups: `traveler`, `agency`, `admin`
- [x] Lambda config hook for `post_confirmation` trigger

#### Module: `storage`
- [x] S3 buckets: `web`, `media`, `documents`
- [x] CloudFront distributions for `web` and `media` with OAC
- [x] S3 bucket policies scoped to CloudFront only
- [x] Versioning enabled on `documents` bucket

#### Module: `opensearch`
- [x] OpenSearch 2.13 domain in VPC
- [x] Fine-grained access control enabled
- [x] Encryption at rest + in transit + HTTPS enforced
- [x] CloudWatch slow-query log publishing
- [x] AZ awareness for multi-node deployments

#### Environments
- [x] `dev` — small/cheap: single NAT, `db.t3.medium`, single-AZ Redis, single-AZ OpenSearch
- [x] `staging` — medium: multi-AZ RDS, 2-node Redis, 2-node OpenSearch
- [x] `prod` — full HA: `db.r6g.large`, `r6g.large` Redis ×3, `r6g.large` OpenSearch ×3

#### CI/CD
- [x] GitHub Actions workflow: OIDC auth → plan on PR → sequential dev → staging → prod apply
- [x] PR plans posted as PR comments
- [x] Prod gated behind GitHub environment (manual approval)

---

## Remaining work

### Phase 2 — Event-driven / background infrastructure

- [ ] **Lambda functions** — Terraform for each function's IAM role, log group, and EventBridge trigger:
  - `cognito-post-signup` (Cognito trigger)
  - `request-expiry` (EventBridge Scheduler)
  - `notification-dispatcher` (EventBridge rule)
  - `document-processor` (S3 event)
  - `search-indexer` (RDS → EventBridge)
- [ ] **Step Functions** — state machine definitions for:
  - `agency-approval-workflow`
  - `bid-award-workflow`
  - `request-expiry-workflow`
- [ ] **EventBridge** — custom event bus + rules routing business events to Lambda/Step Functions
- [ ] **SES** — verified domain, DKIM, sending configuration set
- [ ] **Pinpoint** — app + push notification channels (APNs, FCM)
- [ ] **AppSync** — GraphQL API for WebSocket subscriptions (bid notifications, live updates)

### Phase 3 — Observability

- [ ] CloudWatch dashboards (EKS cluster, RDS, Redis, OpenSearch)
- [ ] CloudWatch alarms (pod pending > threshold, RDS CPU, Redis memory, 5xx rate)
- [ ] SNS topic for alarm notifications
- [ ] X-Ray tracing group + sampling rules
- [ ] RDS Performance Insights dashboard

### Phase 4 — Application Helm charts

- [ ] Base Helm chart template (used by all services)
- [ ] Per-service `values.yaml` files:
  - `next-web`, `request-service`, `bid-service`, `agency-service`, `admin-service`, `search-service`
- [ ] HPA config per service (target CPU 70%)
- [ ] ALB Ingress resource with routing table
- [ ] ConfigMap + ExternalSecret (or Secrets Manager CSI driver) for app config

### Phase 5 — Security hardening

- [ ] Scope GitHub Actions IAM roles down from `AdministratorAccess` to minimum required policies
- [ ] Kubernetes NetworkPolicy resources (restrict pod-to-pod traffic)
- [ ] AWS WAF WebACL attached to CloudFront + ALB
- [ ] CloudTrail trail with S3 + CloudWatch delivery
- [ ] KMS CMK for RDS, ElastiCache, S3 (replace default `AES256`)
- [ ] Secrets Manager rotation for RDS credentials

### Phase 6 — DNS & TLS

- [ ] Route 53 hosted zone
- [ ] ACM certificates (us-east-1 for CloudFront, regional for ALB)
- [ ] CloudFront alternate domain names
- [ ] ALB listener with HTTPS + certificate

---

## How to get started on a new AWS account

```bash
# 1. Bootstrap — run once manually (local state)
cd infra/bootstrap
terraform init
terraform apply -var="github_org=YOUR_ORG" -var="github_repo=YOUR_REPO"

# 2. Copy tfstate_bucket output value into each backend.tf
# infra/environments/dev/backend.tf
# infra/environments/staging/backend.tf
# infra/environments/prod/backend.tf

# 3. Add AWS_ROLE_ARN secret to each GitHub environment
#    (use the role ARNs from: terraform output github_actions_role_arns)

# 4. Deploy dev
cd infra/environments/dev
terraform init
terraform plan
terraform apply
```

---

## Key decisions made

| Decision | Choice | Rationale |
|---|---|---|
| IaC tool | Terraform (pure, no Terragrunt) | EKS module ecosystem maturity; Helm provider; no extra tooling |
| Compute | EKS managed node groups + Karpenter | Flexibility, IRSA, cost-efficient node scaling |
| State | S3 + DynamoDB | Standard, already in the AWS account |
| CI auth | GitHub OIDC | No stored secrets; token expires after each job |
| Environment isolation | Separate state files per env | Avoids workspace confusion; safer blast radius |
| Env progression | dev → staging → prod sequential in CI | Staging must pass before prod gate opens |
| Module source | `terraform-aws-modules/*` | Battle-tested, well-maintained, covers EKS/VPC/RDS cleanly |
