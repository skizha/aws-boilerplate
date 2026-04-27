# Fill in bucket with the value from: cd infra/bootstrap && terraform output tfstate_bucket
terraform {
  backend "s3" {
    bucket         = "myapp-tfstate-992382469539"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "myapp-tfstate-lock"
    encrypt        = true
  }
}
