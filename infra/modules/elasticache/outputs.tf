output "primary_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  value = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "port" {
  value = 6379
}
