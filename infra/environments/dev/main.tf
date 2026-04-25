locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
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
  single_nat_gateway   = true   # single NAT saves ~$100/month in dev

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
  system_node_instance_types = ["m5.large"]

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

  karpenter_instance_types = ["m5.large", "m5.xlarge", "m6i.large"]
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
  multi_az              = false   # multi_az in staging/prod

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
  num_cache_clusters = 1    # single node in dev

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

  cloudfront_price_class = "PriceClass_100"   # US/EU only in dev

  tags = local.common_tags
}

# ── OpenSearch ────────────────────────────────────────────────────────────────

module "opensearch" {
  source = "../../modules/opensearch"

  project     = var.project
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = [module.networking.private_subnet_ids[0]]   # single-AZ in dev

  allowed_security_group_ids = [module.eks.node_security_group_id]

  master_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  instance_type   = "t3.small.search"
  instance_count  = 1
  volume_size_gb  = 20

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
