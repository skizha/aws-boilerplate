# Fill in bucket with the value from: cd infra/bootstrap && terraform output tfstate_bucket
terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "myapp-tfstate-lock"
    encrypt        = true
  }
}
