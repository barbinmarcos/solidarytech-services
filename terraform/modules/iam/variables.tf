variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "velero_bucket_arn" {
  description = "ARN do bucket S3 utilizado pelo Velero para backups"
  type        = string
}
