variable "project" { type = string }
variable "environment" { type = string }

variable "callback_urls" {
  type    = list(string)
  default = ["http://localhost:3000/api/auth/callback/cognito"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:3000"]
}

variable "post_confirmation_lambda_arn" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
