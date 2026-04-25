output "proxy_endpoint" {
  value = aws_db_proxy.this.endpoint
}

output "db_security_group_id" {
  value = aws_security_group.rds.id
}

output "db_credentials_secret_arn" {
  value     = aws_secretsmanager_secret.db.arn
  sensitive = true
}

output "db_instance_id" {
  value = module.rds.db_instance_identifier
}
