variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "myapp"
}

variable "github_org" {
  type        = string
  description = "GitHub organisation or username that owns the repo"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (without the org prefix)"
}
