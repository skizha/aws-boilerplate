# Run this ONCE manually with local state before any environment applies.
# After apply, note the bucket name from outputs and fill in backend.tf for each environment.
#
# cd infra/bootstrap
# terraform init
# terraform apply -var="github_org=YOUR_ORG" -var="github_repo=YOUR_REPO"

terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── Remote state backend ──────────────────────────────────────────────────────

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# OpenSearch domains in a VPC require this account-level service-linked role.
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchservice.amazonaws.com"
}

# ── GitHub Actions OIDC ───────────────────────────────────────────────────────

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

# ── IAM roles for GitHub Actions (one per environment) ───────────────────────

locals {
  environments = ["dev", "staging", "prod"]
}

data "aws_iam_policy_document" "github_actions_assume" {
  for_each = toset(local.environments)

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Locks to a specific GitHub environment — prevents cross-env privilege escalation
      values = ["repo:${var.github_org}/${var.github_repo}:environment:${each.key}"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  for_each           = toset(local.environments)
  name               = "${var.project}-github-actions-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume[each.key].json
}

# AdministratorAccess is intentionally broad for the bootstrap phase.
# Scope this down to specific service permissions before production hardening.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  for_each   = toset(local.environments)
  role       = aws_iam_role.github_actions[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
