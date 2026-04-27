locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
}

module "networking" {
  source = "../../modules/networking"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = "10.2.0.0/16"
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnet_cidrs = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  public_subnet_cidrs  = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
  single_nat_gateway   = false # one NAT per AZ for HA

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  cluster_version            = "1.31"
  system_node_instance_types = ["m5.xlarge"]

  app_service_accounts = {
    request-service = { policy_arns = { secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" } }
    bid-service     = { policy_arns = { secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" } }
    agency-service  = { policy_arns = { secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite", s3 = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" } }
    admin-service   = { policy_arns = { secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" } }
    search-service  = { policy_arns = { secrets = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" } }
    next-web        = { policy_arns = {} }
  }

  tags = local.common_tags
}

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

  karpenter_instance_types = ["m5.xlarge", "m5.2xlarge", "m6i.xlarge", "m6i.2xlarge", "m6a.xlarge"]
}

module "rds" {
  source = "../../modules/rds"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  instance_class        = "db.r6g.large"
  allocated_storage     = 100
  max_allocated_storage = 1000
  multi_az              = true

  tags = local.common_tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  node_type          = "cache.r6g.large"
  num_cache_clusters = 3 # 1 primary + 2 replicas across AZs

  tags = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  project     = var.project
  environment = var.environment

  callback_urls = ["https://example.com/api/auth/callback/cognito"]
  logout_urls   = ["https://example.com"]

  tags = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  project                = var.project
  environment            = var.environment
  cloudfront_price_class = "PriceClass_All"

  tags = local.common_tags
}

module "opensearch" {
  source = "../../modules/opensearch"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  master_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  instance_type   = "r6g.large.search"
  instance_count  = 3
  volume_size_gb  = 100

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
