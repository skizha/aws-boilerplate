output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "web_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "mobile_client_id" {
  value = aws_cognito_user_pool_client.mobile.id
}

output "domain" {
  value = aws_cognito_user_pool_domain.this.domain
}
