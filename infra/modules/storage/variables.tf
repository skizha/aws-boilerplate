variable "project" { type = string }
variable "environment" { type = string }

variable "cloudfront_price_class" {
  type    = string
  default = "PriceClass_All"
}

variable "tags" {
  type    = map(string)
  default = {}
}
