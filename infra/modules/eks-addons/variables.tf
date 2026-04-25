variable "project" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "cluster_name" { type = string }
variable "cluster_endpoint" { type = string }
variable "vpc_id" { type = string }

variable "karpenter_irsa_arn" { type = string }
variable "karpenter_node_iam_role_name" { type = string }
variable "aws_lbc_irsa_arn" { type = string }

variable "karpenter_version" {
  type    = string
  default = "1.0.0"
}

variable "karpenter_instance_types" {
  type    = list(string)
  default = ["m5.large", "m5.xlarge", "m5.2xlarge", "m6i.large", "m6i.xlarge"]
}

variable "aws_lbc_version" {
  type    = string
  default = "1.8.0"
}

variable "metrics_server_version" {
  type    = string
  default = "3.12.0"
}

variable "fluent_bit_version" {
  type    = string
  default = "0.1.32"
}
