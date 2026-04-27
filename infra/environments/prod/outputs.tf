output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "rds_proxy_endpoint" {
  value = module.rds.proxy_endpoint
}

output "redis_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "opensearch_endpoint" {
  value = module.opensearch.endpoint
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_web_client_id" {
  value = module.cognito.web_client_id
}

output "web_cloudfront_domain" {
  value = module.storage.web_cloudfront_domain
}

output "app_irsa_role_arns" {
  value = module.eks.app_irsa_role_arns
}
