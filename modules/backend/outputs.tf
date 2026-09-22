output "alb_dns_name" {
  value = aws_lb.backend.dns_name
}

output "task_role_id" {
  description = "Used by other modules to attach extra IAM policies (CloudFront signing, Kinesis put) to the backend task role"
  value       = aws_iam_role.task.id
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.backend.name
}
