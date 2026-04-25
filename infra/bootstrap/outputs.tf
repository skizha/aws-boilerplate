output "tfstate_bucket" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "Paste this into backend.tf for each environment"
}

output "tfstate_lock_table" {
  value = aws_dynamodb_table.tfstate_lock.name
}

output "github_actions_role_arns" {
  value = { for env, role in aws_iam_role.github_actions : env => role.arn }
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}
