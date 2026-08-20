variable "aws_region" {
  description = "AWS region used by the SolidaryTech infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "S3 bucket used to store Terraform remote state"
  type        = string
  default     = "solidarytech-tf-state-212792011616"
}
