terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-${var.environment}"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required for AWS Load Balancer Controller to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                                    = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                           = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}"   = "shared"
    "karpenter.sh/discovery"                                    = "${var.project}-${var.environment}"
  }

  tags = var.tags
}
