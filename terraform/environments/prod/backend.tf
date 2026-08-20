terraform {
  backend "s3" {
    bucket  = "solidarytech-tf-state-212792011616"
    key     = "environments/prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
