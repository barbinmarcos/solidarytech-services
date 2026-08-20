resource "aws_eks_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids = var.subnet_ids

    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

#
# Managed Node Group
#

resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name

  node_group_name = "${var.project_name}-${var.environment}-nodes"

  node_role_arn = var.node_role_arn

  subnet_ids = var.subnet_ids

  instance_types = var.instance_types

  capacity_type = "ON_DEMAND"

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = var.environment
    project     = var.project_name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-node-group"
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}

#
# Access Entry - usuário administrador
#

resource "aws_eks_access_entry" "admin" {
  cluster_name = aws_eks_cluster.main.name

  principal_arn = var.admin_principal_arn

  type = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name = aws_eks_cluster.main.name

  principal_arn = var.admin_principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.admin
  ]
}

#
# Add-ons
#

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [
    aws_eks_node_group.main
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [
    aws_eks_node_group.main
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.main
  ]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [
    aws_eks_node_group.main
  ]
}

resource "aws_eks_pod_identity_association" "volunteer" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "solidarytech"
  service_account = "volunteer-service"

  role_arn = var.volunteer_service_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}

resource "aws_eks_pod_identity_association" "donation" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "solidarytech"
  service_account = "donation-service"

  role_arn = var.donation_service_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}
