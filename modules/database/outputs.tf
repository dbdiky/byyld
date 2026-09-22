output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials - reference this from the backend task definition"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
