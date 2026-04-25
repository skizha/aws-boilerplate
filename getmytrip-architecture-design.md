# GetMyTrip — Architecture Design Document

**Version:** 2.0
**Date:** 2026-04-24
**Status:** Draft
**Targets:** Sub-1-second page/screen loads · Web + Mobile · Maximize managed AWS services

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Principles](#2-architecture-principles)
3. [Architecture Diagram](#3-architecture-diagram)
4. [System Layers](#4-system-layers)
   - 4.1 [Client Layer](#41-client-layer)
   - 4.2 [Edge & Delivery Layer](#42-edge--delivery-layer)
   - 4.3 [Authentication](#43-authentication--amazon-cognito)
   - 4.4 [Compute Layer](#44-compute-layer)
   - 4.5 [Data Layer](#45-data-layer)
   - 4.6 [Notifications](#46-notifications)
5. [CI/CD Pipeline](#5-cicd-pipeline)
6. [Observability](#6-observability)
7. [Security](#7-security)
8. [Infrastructure as Code](#8-infrastructure-as-code)
9. [Performance Strategy](#9-performance-strategy)
10. [Decision Log](#10-decision-log)
11. [AWS Services Summary](#11-aws-services-summary)

---

## 1. Overview

GetMyTrip is a travel marketplace platform connecting travelers and travel agencies. Travelers post trip requests; agencies submit competitive bids. The platform operates across web and mobile with a real-time bidding experience driven by WebSocket subscriptions.

The architecture is **fully managed-AWS**, prioritising operational simplicity, zero cold starts for user-facing APIs, and global edge delivery to meet the sub-1-second load target.

---

## 2. Architecture Principles

| # | Principle | Rationale |
|---|-----------|-----------|
| 1 | **Prefer managed AWS services** | Use what AWS provides before building it — eliminates ops burden and accelerates delivery |
| 2 | **Edge-first delivery** | Serve content as close to the user as possible via CloudFront (600+ global PoPs) |
| 3 | **Always-warm API** | EKS pods with `minReplicas ≥ 2` eliminate cold starts for all user-facing routes; Lambda is reserved for background/event-driven work only |
| 4 | **Cache aggressively** | ElastiCache + CloudFront caching keep hot data at the edge and in-memory |
| 5 | **Shared codebase** | React Native (web + mobile) maximises code reuse across platforms |

---

## 3. Architecture Diagram

> The full interactive diagram is available in [`getmytrip-architecture.excalidraw`](./getmytrip-architecture.excalidraw).

```
┌─────────────────────────────────────────────────────────┐
│                     CLIENTS                              │
│   Browser (Next.js Web App)    React Native Mobile App  │
│                                (iOS + Android)           │
└────────────┬───────────────────────────┬────────────────┘
             │                           │
             ▼                           ▼
┌─────────────────────────────────────────────────────────┐
│              EDGE & DELIVERY LAYER                        │
│   Amazon CloudFront  (CDN — global PoPs)                 │
│   CloudFront Functions (URL rewrites, header auth)       │
│   Lambda@Edge (A/B testing · geo routing · auth headers) │
│   AWS WAF  ·  AWS Shield Standard                        │
└───────────┬──────────────────────────────────────────────┘
            │
  ┌─────────┴──────────┐
  ▼                    ▼
┌──────────────────────────────┐  ┌───────────────────────┐
│  AWS ALB (Ingress)           │  │  S3: getmytrip-web    │
│  AWS Load Balancer Controller│  │  Static assets (JS,   │
│  (routes via K8s Ingress)    │  │  CSS, images) served  │
└──────────────┬───────────────┘  │  via CloudFront        │
               │                  └───────────────────────┘
  ┌────────────┼──────────────┐
  ▼            ▼              ▼
┌──────────────────────────────────────────────────────────────┐
│  AMAZON EKS CLUSTER  (managed control plane + node groups)   │
│                                                              │
│  Namespace: getmytrip                                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Deployments (minReplicas=2, HPA enabled)            │   │
│  │  next-web       request-svc    bid-svc               │   │
│  │  agency-svc     admin-svc      search-svc            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Node scaling: Karpenter (auto-provisions nodes on demand)   │
│  IAM: IRSA — each service account has its own IAM role       │
└────────┬─────────────────────────────────────────────────────┘
         │
  ┌──────┴───────┐
  ▼              ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│  AWS APPSYNC     │ │  AWS LAMBDA      │ │  Amazon ECR          │
│  (real-time)     │ │  (background)    │ │  (container images)  │
│  WebSocket subs  │ │  Cognito triggers│ │                      │
│  bid notifs      │ │  Step Functions  │ │                      │
│  live updates    │ │  EventBridge     │ │                      │
└──────────────────┘ └──────────────────┘ └──────────────────────┘
         │
         ▼
┌─────────────────────┐   ┌──────────────────────────────┐
│  DATA LAYER         │   │  SUPPORTING SERVICES          │
│  RDS PostgreSQL     │   │  Amazon Cognito (auth)        │
│  (Multi-AZ)         │   │  Amazon SES (email)           │
│  RDS Proxy          │   │  Amazon Pinpoint (push/SMS)   │
│  ElastiCache Redis  │   │  Amazon OpenSearch (search)   │
│  S3 (files/docs)    │   └──────────────────────────────┘
└─────────────────────┘
```

---

## 4. System Layers

### 4.1 Client Layer

| Platform | Technology | Notes |
|---|---|---|
| **Web** | Next.js (React) | Runs as always-warm container in EKS (`next start`, `minReplicas=2`); static assets served from S3 via CloudFront |
| **Mobile** | React Native + Expo | Single codebase for iOS and Android; shares business logic with web |
| **Shared UI** | Tamagui or NativeWind | Consistent design system across web and mobile |
| **State management** | React Query (TanStack) | Server-state caching, background refetch, stale-while-revalidate |

**Design rationale:** Next.js runs in EKS as an always-warm Node.js container (`next start`, `minReplicas=2`) — no cold starts, consistent SSR response times. Static assets (JS bundles, CSS, images) are served from S3 via CloudFront. React Native with Expo eliminates separate iOS/Android codebases.

---

### 4.2 Edge & Delivery Layer

> Goal: serve content within ~20–50ms globally.

| Service | Role |
|---|---|
| **Amazon CloudFront** | Global CDN with 600+ PoPs; serves static assets and cached API responses |
| **CloudFront Functions** | Lightweight JS at edge — URL rewrites, redirects, request/response header manipulation |
| **Lambda@Edge** | Full Node.js at edge — SSR for dynamic pages, auth header validation, geo-based routing |
| **AWS Certificate Manager (ACM)** | Free, auto-renewing SSL/TLS certificates — no manual cert management |
| **AWS WAF** | OWASP Top 10 rule sets pre-built; blocks SQLi, XSS, bad bots |
| **AWS Shield Standard** | DDoS protection — included free with CloudFront; no setup required |

**Caching strategy:**

| Content type | Cache location | TTL |
|---|---|---|
| Static HTML/CSS/JS | S3 → CloudFront | Long-lived (content-hashed filenames) |
| Agency profiles | CloudFront | 5 minutes |
| Request listings | CloudFront | 30 seconds |
| Personalised / authenticated responses | Not cached | — |

> CDN invalidation is triggered on data mutations via the deployment pipeline.

---

### 4.3 Authentication — Amazon Cognito

> **Zero custom auth code.** Cognito handles everything.

| Feature | How Cognito provides it |
|---|---|
| Email/password signup + login | User Pools — built-in |
| Google OAuth (social login) | Cognito hosted UI + identity providers |
| JWT tokens | Cognito issues access + refresh tokens automatically |
| Role-based access (traveler / agency / admin) | Cognito Groups + custom claims |
| MFA (optional) | TOTP/SMS — built-in, one config toggle |
| Mobile auth SDK | AWS Amplify Auth SDK (wraps Cognito) |
| Password reset / forgot password | Cognito built-in flow |
| Token refresh | Handled by Amplify SDK automatically |

---

### 4.4 Compute Layer

The compute layer uses a **hybrid model**: always-warm containers for user-facing APIs, managed WebSockets for real-time features, and Lambda for background work.

#### 4.4a User-Facing API — Amazon EKS

Amazon EKS provides a managed Kubernetes control plane. AWS manages the control plane (etcd, API server, scheduler); the team manages worker node groups. Pods run with `minReplicas=2` across multiple AZs — **always warm, zero cold starts**.

**Cluster components:**

| Component | Role |
|---|---|
| **EKS Managed Node Groups** | EC2 worker nodes in private subnets across 3 AZs |
| **Karpenter** | Node auto-scaler — provisions right-sized nodes on demand, terminates idle nodes within minutes |
| **AWS Load Balancer Controller** | Watches Kubernetes `Ingress` resources and provisions ALBs automatically |
| **Application Load Balancer (ALB)** | Entry point for all HTTP/HTTPS traffic; replaces API Gateway for EKS-hosted services |
| **Horizontal Pod Autoscaler (HPA)** | Scales pod replicas based on CPU/memory; works alongside Karpenter |
| **IRSA (IAM Roles for Service Accounts)** | Each Kubernetes service account maps to a scoped IAM role — no shared node-level credentials |

**EKS add-ons:**

| Add-on | Purpose |
|---|---|
| `vpc-cni` | Native AWS VPC networking for pods |
| `coredns` | In-cluster DNS |
| `kube-proxy` | Service networking |
| `aws-ebs-csi-driver` | Persistent volume support |
| `adot` | AWS Distro for OpenTelemetry (metrics + traces) |

**API microservices deployed as Kubernetes Deployments:**

| Service | Responsibility | Min replicas |
|---|---|---|
| `next-web` | Next.js SSR (`next start`) | 2 |
| `request-service` | Create / read / update / search trip requests | 2 |
| `bid-service` | Submit / update / withdraw / award bids | 2 |
| `agency-service` | Registration, profile management | 2 |
| `admin-service` | Approval queue, user management | 1 |
| `search-service` | Query OpenSearch for trip requests | 2 |

**Ingress routing (via AWS Load Balancer Controller):**

```
ALB Ingress (getmytrip.com)
  /api/requests/*   → request-service (ClusterIP)
  /api/bids/*       → bid-service     (ClusterIP)
  /api/agencies/*   → agency-service  (ClusterIP)
  /api/admin/*      → admin-service   (ClusterIP)
  /api/search/*     → search-service  (ClusterIP)
  /*                → next-web        (ClusterIP)
```

**Expected response time profile (always-warm pods):**

| Step | Latency |
|---|---|
| ALB routing overhead | ~3ms |
| EKS pod (warm, `minReplicas=2`) | ~10–30ms |
| ElastiCache hit | ~2–5ms |
| RDS query (cached) | ~10–30ms |
| **Total p95** | **~45–70ms** ✅ |

> **Backend language decision — open:** All three options below run identically on EKS as containers. This must be decided before development begins, based on team expertise and AI/ML roadmap.
>
> | Option | Best when | Trade-off |
> |---|---|---|
> | **Node.js + NestJS** | Team knows TypeScript; want shared types with Next.js | Single-threaded; no ML ecosystem |
> | **Python + FastAPI** | AI/ML features planned; Python team | No shared code with frontend |
> | **Go + Gin** | Maximum throughput and lowest compute cost | Slower to develop; smaller talent pool |

---

#### 4.4b Real-Time Notifications — AWS AppSync

Replaces API Gateway WebSocket. AppSync is a managed GraphQL service with built-in WebSocket subscriptions — no timeout issues, no reconnect logic to build.

| Capability | Implementation |
|---|---|
| Real-time bid arrival notification | Subscription pushed to traveler's browser/app instantly |
| Live bid count update on request page | AppSync mutation triggers all subscribers automatically |
| Mobile push fallback | AppSync → EventBridge → Pinpoint when app is backgrounded |
| Connection management | Fully managed — handles reconnects, scaling, auth |

---

#### 4.4c Background & Event-Driven Work — AWS Lambda

Lambda is used exclusively for background jobs where latency is irrelevant and pay-per-invocation keeps costs low.

| Lambda function | Trigger | Purpose |
|---|---|---|
| `cognito-post-signup` | Cognito trigger | Set user role, create profile record |
| `request-expiry` | EventBridge Scheduler | Close expired requests, notify traveler |
| `notification-dispatcher` | EventBridge rules | Route events → SES email or Pinpoint push |
| `document-processor` | S3 event | Validate/scan uploaded agency documents |
| `search-indexer` | RDS → EventBridge | Sync trip request data to OpenSearch |

**Step Functions workflows (managed orchestration):**

| Workflow | Steps |
|---|---|
| `agency-approval-workflow` | Admin approves → agency status update → welcome email |
| `bid-award-workflow` | Traveler selects bid → mark won/lost → reveal contacts → notify all parties |
| `request-expiry-workflow` | EventBridge Scheduler triggers at deadline → close request → notify traveler |

---

### 4.5 Data Layer

#### Primary Database — Amazon RDS PostgreSQL (Multi-AZ)

| Feature | Detail |
|---|---|
| High availability | Multi-AZ deployment — automatic failover, no manual HA setup |
| Read scaling | Read replica for reporting/analytics queries |
| Connection pooling | RDS Proxy — prevents connection exhaustion as EKS pods scale horizontally |
| Backup | Automated daily backups + point-in-time recovery, managed by AWS |

#### Cache — Amazon ElastiCache for Redis

| Cache use | TTL |
|---|---|
| Agency profile pages | 5 minutes |
| Open trip request listings | 30 seconds |
| Search results | 60 seconds |
| User session data | 24 hours |
| Rate limiting counters | Rolling window |

#### File Storage — Amazon S3

| Bucket | Contents | Access |
|---|---|---|
| `getmytrip-documents` | Agency registration documents | Private; pre-signed URLs for admin |
| `getmytrip-media` | Profile photos, trip images | Public via CloudFront |
| `getmytrip-web` | Next.js static build output | Public via CloudFront |

#### Search — Amazon OpenSearch Service

- Powers the trip request marketplace search (filter by destination, dates, trip type, budget)
- Managed cluster — no Elasticsearch ops; automated upgrades and snapshots
- Data synced from RDS via Lambda on create / update / delete events

---

### 4.6 Notifications

> **No custom notification infrastructure.** Pinpoint and SES handle all delivery.

| Channel | Service | Use case |
|---|---|---|
| **Transactional email** | Amazon SES | Bid received, bid won/lost, agency approval, password reset |
| **Push notifications** | Amazon Pinpoint | Mobile: new bid, request expiring, bid selected |
| **SMS (optional)** | Amazon Pinpoint | Critical alerts (bid won, request deadline) |
| **Event routing** | Amazon EventBridge | Decoupled: business events trigger notification Lambda |

Email templates are managed in SES; no custom email server required.

---

## 5. CI/CD Pipeline

| Stage | Service |
|---|---|
| Source control | GitHub |
| Pipeline orchestration | GitHub Actions |
| AWS authentication | OIDC federation — short-lived tokens, no stored AWS keys |
| Next.js deployment | GitHub Actions → `docker build` → ECR → `helm upgrade` to EKS |
| Static asset deployment | GitHub Actions → `next build` → `aws s3 sync` → CloudFront invalidation |
| API services deployment | GitHub Actions → `docker build` → ECR → `helm upgrade` to EKS |
| Lambda deployment | GitHub Actions → `cdk deploy` |
| Infrastructure (IaC) | GitHub Actions → `cdk deploy` (per environment: dev / staging / prod) |
| PR preview environments | GitHub Actions → `helm install` into isolated EKS namespace per PR; torn down on PR close |
| Mobile build | Expo EAS Build (cloud build for iOS/Android binaries) |
| Mobile distribution | EAS Submit → App Store + Play Store |
| Helm charts | One chart per service; values files per environment (`values.dev.yaml`, `values.prod.yaml`) |

**Branch-to-environment mapping:**

| Git event | Deployment target |
|---|---|
| Push to `main` | Production |
| Push to `staging` | Staging |
| PR opened | PR preview namespace in EKS (isolated) |
| PR closed | PR preview namespace torn down (`helm uninstall`) |

**OIDC authentication flow (no long-lived credentials):**

```
GitHub Actions requests short-lived AWS token via OIDC
  → AWS IAM verifies token against GitHub's OIDC provider
  → Assumes a scoped IAM role (e.g. github-actions-deploy)
  → Token expires after the job — nothing stored in GitHub Secrets
```

> Configured once in CDK: create an `OidcProvider` + IAM role with a condition locking it to your GitHub org/repo.

---

## 6. Observability

| Concern | Service |
|---|---|
| Container logs | Amazon CloudWatch Logs — Fluent Bit DaemonSet ships pod logs to CloudWatch Log Groups |
| Cluster metrics | CloudWatch Container Insights for EKS — node, pod, and namespace-level CPU/memory |
| Lambda / ALB logs | CloudWatch Logs (auto-streamed) |
| Distributed tracing | AWS X-Ray via ADOT collector — traces: CloudFront → ALB → EKS pod → RDS |
| Dashboards | CloudWatch Dashboards |
| Error alerting | CloudWatch Alarm → SNS → PagerDuty / email |
| RDS performance | Amazon RDS Performance Insights (slow query detection) |
| Node scaling events | Karpenter emits CloudWatch metrics; alert on pending pods > threshold |

---

## 7. Security

| Concern | Service | Notes |
|---|---|---|
| Secrets & credentials | AWS Secrets Manager | DB passwords, API keys — auto-rotated |
| Encryption at rest | AWS KMS | S3, RDS, ElastiCache all encrypted with KMS keys |
| Encryption in transit | ACM + TLS 1.3 | Enforced at CloudFront |
| IAM least-privilege | AWS IAM + IRSA | Each EKS service account maps to a scoped IAM role (IRSA); separate roles for Lambda and AppSync |
| Network isolation | VPC + Security Groups + K8s NetworkPolicy | EKS nodes in private subnets; pods communicate via NetworkPolicy; only ALB is public-facing |
| API protection | AWS WAF | Rate limiting, geo-blocking, managed rule sets |
| DDoS | AWS Shield Standard | Free, always-on |
| Audit logging | AWS CloudTrail | All API calls to AWS services are logged |

---

## 8. Infrastructure as Code

- **AWS CDK (TypeScript)** — all infrastructure defined as code, versioned alongside application code
- Separate CDK stacks per environment: `dev`, `staging`, `production`
- Single command deploys the full stack: `cdk deploy`

---

## 9. Performance Strategy

### Techniques

| Technique | Implementation |
|---|---|
| Edge delivery | CloudFront serves from nearest PoP (~30–80ms) |
| Static generation | Next.js SSG pre-renders pages at build time |
| Incremental Static Regeneration | Agency profiles and request pages revalidated in background |
| API response caching | CloudFront caches GET responses for listings |
| In-memory caching | ElastiCache Redis for hot DB queries |
| Always-warm API | EKS pods with `minReplicas=2` — zero cold starts, consistent ~45–70ms API response |
| Real-time without polling | AppSync WebSocket subscriptions — instant push, no client polling |
| Image optimisation | Next.js Image component + CloudFront image sizing |
| Connection pooling | RDS Proxy prevents EKS pods from exhausting DB connections at scale |
| Lazy loading | Non-critical components and routes loaded on demand |
| Bundle splitting | Next.js automatic code splitting per route |

### Performance Targets

| Metric | Target |
|---|---|
| Time to First Byte (TTFB) | < 100ms |
| Largest Contentful Paint (LCP) | < 1.0s |
| API response time (p95) | < 200ms |
| Mobile screen transition | < 300ms |

---

## 10. Decision Log

| Decision | Choice | Alternatives considered | Rationale |
|---|---|---|---|
| Compute for user-facing APIs | Amazon EKS (managed node groups) | App Runner, ECS Fargate, EC2, Lambda | Full Kubernetes flexibility for multi-service routing, zero cold starts via `minReplicas=2`, IRSA for fine-grained IAM, Karpenter for cost-efficient node scaling; accepted trade-off: higher operational surface than App Runner |
| Real-time transport | AWS AppSync (WebSocket) | API Gateway WebSocket, Socket.io self-hosted | No timeout issues; built-in auth; managed reconnects |
| Authentication | Amazon Cognito | Auth0, custom auth | Zero auth code; JWT, OAuth, MFA out of the box |
| Database | RDS PostgreSQL (Multi-AZ) | Aurora Serverless, DynamoDB | Relational model suits marketplace data; Multi-AZ HA managed |
| Search | Amazon OpenSearch | Algolia, self-hosted Elasticsearch | AWS-native; managed ops; cost-effective at scale |
| Frontend framework | Next.js | Remix, Nuxt | SSR + SSG + ISR; strong React ecosystem |
| Mobile | React Native + Expo | Flutter, native iOS/Android | Maximum code sharing with web; single codebase |
| Backend language | **TBD** — Node.js / Python / FastAPI / Go | — | Depends on team expertise and AI/ML roadmap |
| IaC | AWS CDK (TypeScript) | Terraform, CloudFormation | TypeScript across the stack; type-safe infra |

---

## 11. AWS Services Summary

| Category | Services |
|---|---|
| **Delivery** | CloudFront · Lambda@Edge · CloudFront Functions · S3 |
| **API (user-facing)** | EKS (managed node groups) · ALB (AWS Load Balancer Controller) · Karpenter · HPA |
| **Real-time** | AWS AppSync (WebSocket subscriptions) |
| **Background jobs** | Lambda · Step Functions · EventBridge Scheduler |
| **Container registry** | Amazon ECR |
| **Auth** | Cognito User Pools |
| **Database** | RDS PostgreSQL (Multi-AZ) · RDS Proxy · ElastiCache Redis |
| **Search** | OpenSearch Service |
| **Notifications** | SES · Pinpoint |
| **Storage** | S3 |
| **Security** | WAF · Shield · Secrets Manager · KMS · IAM · IRSA · NetworkPolicy · CloudTrail · ACM |
| **Observability** | CloudWatch · CloudWatch Container Insights · X-Ray · ADOT · Fluent Bit |
| **IaC** | CDK (TypeScript) |
| **CI/CD** | GitHub Actions (OIDC → AWS) |
| **Mobile build** | Expo EAS Build |

---

*Architecture Design Document — GetMyTrip v2.0 — Compute: EKS*
