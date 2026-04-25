output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "aws_lbc_role_arn" {
  value = module.irsa_aws_lbc.iam_role_arn
}

output "karpenter_irsa_arn" {
  value = module.karpenter.iam_role_arn
}

output "karpenter_node_iam_role_name" {
  value = module.karpenter.node_iam_role_name
}

output "karpenter_instance_profile_name" {
  value = module.karpenter.instance_profile_name
}

output "app_irsa_role_arns" {
  value = { for k, v in module.irsa_app : k => v.iam_role_arn }
}
