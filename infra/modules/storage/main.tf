terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  cdn_buckets = ["web", "media"]
}

# ── S3 buckets ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "this" {
  for_each = toset(["web", "media", "documents"])
  bucket   = "${var.project}-${each.key}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  tags     = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.this["documents"].id
  versioning_configuration { status = "Enabled" }
}

# ── CloudFront for web and media ──────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = toset(local.cdn_buckets)

  name                              = "${var.project}-${each.key}-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  for_each = toset(local.cdn_buckets)

  enabled             = true
  default_root_object = each.key == "web" ? "index.html" : null
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.this[each.key].bucket_regional_domain_name
    origin_id                = each.key
    origin_access_control_id = aws_cloudfront_origin_access_control.this[each.key].id
  }

  default_cache_behavior {
    target_origin_id       = each.key
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = each.key == "web" ? 86400 : 3600
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

resource "aws_s3_bucket_policy" "cdn" {
  for_each = toset(local.cdn_buckets)
  bucket   = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.this[each.key].arn}/*"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.this[each.key].arn
        }
      }
    }]
  })
}
