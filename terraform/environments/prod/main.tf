module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b"
  ]
}
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment

  repositories = [
    "ngo-service",
    "donation-service",
    "volunteer-service"
  ]
}
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment

  table_name = "solidarytech-volunteers"
}
module "sqs" {
  source = "../../modules/sqs"

  project_name = var.project_name
  environment  = var.environment

  queue_name = "solidarytech-donation-events"
}
module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  db_name     = "solidarytech"
  db_username = "solidarytech_admin"
  db_password = var.db_password
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment

  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arn
}

module "eks" {
  source = "../../modules/eks"

  project_name = var.project_name
  environment  = var.environment

  # Nodes inicialmente nas subnets públicas
  # porque ainda não configuramos NAT Gateway/VPC Endpoints
  subnet_ids = module.vpc.public_subnet_ids

  # IAM Roles
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn

  # Acesso administrativo ao cluster
  admin_principal_arn = "arn:aws:iam::212792011616:user/barbin"

  # Pod Identity
  volunteer_service_role_arn = module.iam.volunteer_service_role_arn
  donation_service_role_arn  = module.iam.donation_service_role_arn

  # Managed Node Group
  instance_types = [
    "t3.small"
  ]

  desired_size = 1
  min_size     = 1
  max_size     = 2
}
