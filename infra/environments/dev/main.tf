locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }

  next_web_labels = {
    app = "next-web"
  }

  next_web_image = "${aws_ecr_repository.next_web.repository_url}:${var.next_web_image_tag}"
}

# ── Networking ────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  single_nat_gateway   = true # single NAT saves ~$100/month in dev

  tags = local.common_tags
}

# ── EKS ───────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  cluster_version            = "1.31"
  system_node_instance_types = ["t3.medium"]
  system_node_min_size       = 1
  system_node_max_size       = 2
  system_node_desired_size   = 1

  app_service_accounts = {
    request-service = {
      policy_arns = {
        secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
      }
    }
    bid-service = {
      policy_arns = {
        secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
      }
    }
    agency-service = {
      policy_arns = {
        secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
        s3      = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
      }
    }
    admin-service = {
      policy_arns = {
        secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
      }
    }
    search-service = {
      policy_arns = {
        secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
      }
    }
    next-web = {
      policy_arns = {}
    }
  }

  tags = local.common_tags
}

# ── EKS Add-ons ───────────────────────────────────────────────────────────────

module "eks_addons" {
  source = "../../modules/eks-addons"

  project          = var.project
  environment      = var.environment
  aws_region       = var.aws_region
  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  vpc_id           = module.networking.vpc_id

  karpenter_irsa_arn           = module.eks.karpenter_irsa_arn
  karpenter_node_iam_role_name = module.eks.karpenter_node_iam_role_name
  aws_lbc_irsa_arn             = module.eks.aws_lbc_role_arn

  karpenter_instance_types = ["t3.medium", "t3.large"]
  karpenter_capacity_types = ["on-demand"]
}

# ── Next.js Web App ───────────────────────────────────────────────────────────

resource "aws_ecr_repository" "next_web" {
  name                 = "${var.project}/${var.environment}/next-web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "next_web" {
  repository = aws_ecr_repository.next_web.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "kubernetes_service_account_v1" "next_web" {
  metadata {
    name      = "next-web"
    namespace = var.project
    annotations = {
      "eks.amazonaws.com/role-arn" = module.eks.app_irsa_role_arns["next-web"]
    }
    labels = local.next_web_labels
  }

  automount_service_account_token = true

  depends_on = [module.eks_addons]
}

resource "kubernetes_deployment_v1" "next_web" {
  wait_for_rollout = false

  metadata {
    name      = "next-web"
    namespace = var.project
    labels    = local.next_web_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.next_web_labels
    }

    template {
      metadata {
        labels = local.next_web_labels
      }

      spec {
        service_account_name = kubernetes_service_account_v1.next_web.metadata[0].name

        toleration {
          key      = "CriticalAddonsOnly"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }

        container {
          name              = "next-web"
          image             = local.next_web_image
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "NEXT_TELEMETRY_DISABLED"
            value = "1"
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          env {
            name  = "COGNITO_USER_POOL_ID"
            value = module.cognito.user_pool_id
          }

          env {
            name  = "COGNITO_WEB_CLIENT_ID"
            value = module.cognito.web_client_id
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 20
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "next_web" {
  metadata {
    name      = "next-web"
    namespace = var.project
    labels    = local.next_web_labels
  }

  spec {
    selector = local.next_web_labels

    port {
      name        = "http"
      port        = 80
      target_port = 3000
    }

    type = "ClusterIP"
  }

  depends_on = [module.eks_addons]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "next_web" {
  metadata {
    name      = "next-web"
    namespace = var.project
    labels    = local.next_web_labels
  }

  spec {
    min_replicas = 1
    max_replicas = 2

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.next_web.metadata[0].name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "next_web" {
  metadata {
    name      = "next-web"
    namespace = var.project
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/tags"             = "Project=${var.project},Environment=${var.environment}"
    }
    labels = local.next_web_labels
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.next_web.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.eks_addons]
}

# ── RDS PostgreSQL ────────────────────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  allowed_security_group_ids = [module.eks.node_security_group_id]

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false # multi_az in staging/prod

  tags = local.common_tags
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────

module "elasticache" {
  source = "../../modules/elasticache"

  project     = var.project
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids

  allowed_security_group_ids = [module.eks.node_security_group_id]

  node_type          = "cache.t3.micro"
  num_cache_clusters = 1 # single node in dev

  tags = local.common_tags
}

# ── Cognito ───────────────────────────────────────────────────────────────────

module "cognito" {
  source = "../../modules/cognito"

  project     = var.project
  environment = var.environment

  callback_urls = ["http://localhost:3000/api/auth/callback/cognito"]
  logout_urls   = ["http://localhost:3000"]

  tags = local.common_tags
}

# ── S3 + CloudFront ───────────────────────────────────────────────────────────

module "storage" {
  source = "../../modules/storage"

  project     = var.project
  environment = var.environment

  cloudfront_price_class = "PriceClass_100" # US/EU only in dev

  tags = local.common_tags
}

# ── OpenSearch ────────────────────────────────────────────────────────────────

module "opensearch" {
  source = "../../modules/opensearch"

  project     = var.project
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = [module.networking.private_subnet_ids[0]] # single-AZ in dev

  allowed_security_group_ids = [module.eks.node_security_group_id]

  master_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  instance_type   = "t3.small.search"
  instance_count  = 1
  volume_size_gb  = 20

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
