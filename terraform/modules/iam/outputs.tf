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
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "velero_role_arn" {
  description = "ARN da IAM Role usada pelo Velero via EKS Pod Identity"
  value       = aws_iam_role.velero.arn
}
