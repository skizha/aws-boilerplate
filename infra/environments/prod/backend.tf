terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "getmytrip-tfstate-lock"
    encrypt        = true
  }
}
