variable "aws_region" {
  description = "AWS region for SolidaryTech production"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "solidarytech"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "solidarytech"
}
