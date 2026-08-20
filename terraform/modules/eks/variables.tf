variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "admin_principal_arn" {
  description = "IAM principal that will receive cluster-admin access"
  type        = string
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "desired_size" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "volunteer_service_role_arn" {
  type = string
}

variable "donation_service_role_arn" {
  type = string
}
