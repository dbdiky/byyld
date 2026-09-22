output "backend_alb_dns_name" {
  value = module.backend.alb_dns_name
}

output "cloudfront_domain_name" {
  value = module.delivery.distribution_domain_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "raw_uploads_bucket" {
  value = module.storage.raw_uploads_bucket_name
}

output "processed_bucket" {
  value = module.storage.processed_bucket_name
}

output "play_events_stream_name" {
  value = module.data_pipeline.stream_name
}
