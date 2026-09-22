output "lambda_function_arn" {
  value = aws_lambda_function.transcode_trigger.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.transcode_trigger.function_name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.transcoding.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.transcode.arn
}
