variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }
variable "master_user_arn" { type = string }

variable "engine_version" {
  type    = string
  default = "OpenSearch_2.13"
}

variable "instance_type" {
  type    = string
  default = "t3.small.search"
}

variable "instance_count" {
  type    = number
  default = 1
}

variable "volume_size_gb" {
  type    = number
  default = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
