terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "myapp-tfstate-lock"
    encrypt        = true
  }
}
