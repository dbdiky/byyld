output "distribution_domain_name" {
  value = aws_cloudfront_distribution.audio.domain_name
}

output "distribution_id" {
  value = aws_cloudfront_distribution.audio.id
}

output "signing_key_group_id" {
  value = aws_cloudfront_key_group.signing.id
}
