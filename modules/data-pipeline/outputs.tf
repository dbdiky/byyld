output "stream_name" {
  value = aws_kinesis_stream.play_events.name
}

output "stream_arn" {
  value = aws_kinesis_stream.play_events.arn
}

output "archive_bucket_name" {
  value = aws_s3_bucket.play_events_archive.bucket
}
