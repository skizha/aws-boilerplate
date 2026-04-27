variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "myapp"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "next_web_image_tag" {
  type        = string
  description = "Container image tag for the Next.js web app deployed to dev EKS."
  default     = "latest"
}
