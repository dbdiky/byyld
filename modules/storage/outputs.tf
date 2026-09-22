output "raw_uploads_bucket_name" {
  value = aws_s3_bucket.raw_uploads.bucket
}

output "raw_uploads_bucket_arn" {
  value = aws_s3_bucket.raw_uploads.arn
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed.bucket
}

output "processed_bucket_arn" {
  value = aws_s3_bucket.processed.arn
}

output "processed_bucket_regional_domain_name" {
  description = "Used as the CloudFront origin"
  value       = aws_s3_bucket.processed.bucket_regional_domain_name
}
