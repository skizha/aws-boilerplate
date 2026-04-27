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

output "next_web_ecr_repository_url" {
  value = aws_ecr_repository.next_web.repository_url
}

output "next_web_alb_hostname" {
  value = try(kubernetes_ingress_v1.next_web.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "app_irsa_role_arns" {
  value = module.eks.app_irsa_role_arns
}
