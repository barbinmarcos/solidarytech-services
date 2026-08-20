variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "repositories" {
  description = "ECR repositories to create"
  type        = list(string)
}
