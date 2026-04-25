variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "system_node_instance_types" {
  type    = list(string)
  default = ["m5.large"]
}

variable "app_service_accounts" {
  description = "Map of service-account name → IAM policy ARNs for IRSA"
  type = map(object({
    policy_arns = map(string)
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
