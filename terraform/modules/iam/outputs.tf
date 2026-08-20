output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node.arn
}

output "volunteer_service_role_arn" {
  value = aws_iam_role.volunteer_service.arn
}

output "donation_service_role_arn" {
  value = aws_iam_role.donation_service.arn
}
