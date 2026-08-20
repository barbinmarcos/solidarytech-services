#
# EKS Cluster Role
#

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

#
# EKS Node Role
#

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

#
# Pod Identity Trust Policy
#

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

#
# Volunteer Service -> DynamoDB
#

resource "aws_iam_role" "volunteer_service" {
  name = "${var.project_name}-${var.environment}-volunteer-pod-role"

  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-volunteer-pod-role"
  }
}

data "aws_iam_policy_document" "volunteer_dynamodb" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]

    resources = [
      var.dynamodb_table_arn,
      "${var.dynamodb_table_arn}/index/*"
    ]
  }
}

resource "aws_iam_policy" "volunteer_dynamodb" {
  name = "${var.project_name}-${var.environment}-volunteer-dynamodb"

  policy = data.aws_iam_policy_document.volunteer_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "volunteer_dynamodb" {
  role       = aws_iam_role.volunteer_service.name
  policy_arn = aws_iam_policy.volunteer_dynamodb.arn
}

#
# Donation Service -> SQS
#

resource "aws_iam_role" "donation_service" {
  name = "${var.project_name}-${var.environment}-donation-pod-role"

  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-donation-pod-role"
  }
}

data "aws_iam_policy_document" "donation_sqs" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes"
    ]

    resources = [
      var.sqs_queue_arn
    ]
  }
}

resource "aws_iam_policy" "donation_sqs" {
  name = "${var.project_name}-${var.environment}-donation-sqs"

  policy = data.aws_iam_policy_document.donation_sqs.json
}

resource "aws_iam_role_policy_attachment" "donation_sqs" {
  role       = aws_iam_role.donation_service.name
  policy_arn = aws_iam_policy.donation_sqs.arn
}
