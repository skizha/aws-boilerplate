terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-redis"
  description = "ElastiCache Redis inbound from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-${var.environment}"
  description          = "${var.project} ${var.environment} Redis"

  node_type          = var.node_type
  num_cache_clusters = var.num_cache_clusters
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  engine_version       = "7.1"
  parameter_group_name = "default.redis7"

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = var.num_cache_clusters > 1

  maintenance_window       = "tue:03:00-tue:04:00"
  snapshot_window          = "04:00-05:00"
  snapshot_retention_limit = var.environment == "prod" ? 7 : 1

  tags = var.tags
}
