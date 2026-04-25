terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project}-${var.environment}"
  cluster_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  # Dedicated system node group — on-demand only, for cluster-critical pods (CoreDNS, Karpenter)
  # Application workloads are provisioned by Karpenter, not by this managed group
  eks_managed_node_groups = {
    system = {
      name           = "system"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      labels = { role = "system" }

      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = "${var.project}-${var.environment}"
  }

  enable_cluster_creator_admin_permissions = true

  tags = merge(var.tags, {
    "karpenter.sh/discovery" = "${var.project}-${var.environment}"
  })
}

# ── Karpenter (node autoscaler) ───────────────────────────────────────────────

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

# ── IRSA: EBS CSI Driver ──────────────────────────────────────────────────────

module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.project}-${var.environment}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# ── IRSA: AWS Load Balancer Controller ────────────────────────────────────────

module "irsa_aws_lbc" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.project}-${var.environment}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# ── IRSA: Application service accounts ───────────────────────────────────────

module "irsa_app" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  for_each = var.app_service_accounts

  role_name        = "${var.project}-${var.environment}-${each.key}"
  role_policy_arns = each.value.policy_arns

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.project}:${each.key}"]
    }
  }

  tags = var.tags
}
