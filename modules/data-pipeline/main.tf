locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_region" "current" {}

# The play-event stream. Every track playback emits one record here:
# { track_id, artist_id, subscriber_id, bitrate_kbps, timestamp, duration_played_seconds }
resource "aws_kinesis_stream" "play_events" {
  name             = "${local.name_prefix}-play-events"
  shard_count      = var.shard_count
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-play-events"
  })
}

# Raw archive bucket - the permanent, immutable record of every play event.
# This is the audit trail behind "we paid you for exactly these N streams."
resource "aws_s3_bucket" "play_events_archive" {
  bucket = "${local.name_prefix}-play-events-archive"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-play-events-archive"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "play_events_archive" {
  bucket = aws_s3_bucket.play_events_archive.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

resource "aws_iam_role" "firehose" {
  name = "${local.name_prefix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "${local.name_prefix}-firehose-s3-write"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.play_events_archive.arn,
          "${aws_s3_bucket.play_events_archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = [aws_kinesis_stream.play_events.arn]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "play_events_to_s3" {
  name        = "${local.name_prefix}-play-events-to-s3"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.play_events.arn
    role_arn            = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.play_events_archive.arn
    prefix     = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    buffering_size     = 64
    buffering_interval = 300
    compression_format = "GZIP"
  }

  tags = var.tags
}

# Lambda consumer: reads off the same Kinesis stream and aggregates play counts into Postgres
# on a rolling basis. This feeds the payout calculation batch job, kept separate from the raw archive.
resource "aws_iam_role" "aggregator_lambda" {
  name = "${local.name_prefix}-play-events-aggregator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "aggregator_lambda_basic" {
  role       = aws_iam_role.aggregator_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "aggregator_lambda_vpc" {
  role       = aws_iam_role.aggregator_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "aggregator_lambda_kinesis" {
  name = "${local.name_prefix}-aggregator-kinesis-read"
  role = aws_iam_role.aggregator_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = [aws_kinesis_stream.play_events.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.db_secret_arn]
      }
    ]
  })
}

data "archive_file" "aggregator_placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/aggregator_placeholder.zip"

  source {
    content  = <<-EOF
      def handler(event, context):
          # TODO: for each Kinesis record, decode the play event and upsert aggregated
          # play counts into Postgres (e.g. an `play_count_rollups` table keyed by
          # track_id + billing_period), which the payout batch job later queries.
          print(f"Received {len(event.get('Records', []))} records")
          return {"status": "processed"}
    EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "aggregator" {
  function_name = "${local.name_prefix}-play-events-aggregator"
  role          = aws_iam_role.aggregator_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.aggregator_placeholder.output_path
  source_code_hash = data.archive_file.aggregator_placeholder.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.backend_security_group_id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = var.db_secret_arn
    }
  }

  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "aggregator_trigger" {
  event_source_arn  = aws_kinesis_stream.play_events.arn
  function_name     = aws_lambda_function.aggregator.arn
  starting_position = "LATEST"
  batch_size        = 100

  # Aggregate every few minutes rather than per-record, matching the "scheduled aggregation" decision
  maximum_batching_window_in_seconds = 180
}

# Grant the backend's task role permission to write play events into the stream
resource "aws_iam_role_policy" "backend_kinesis_put" {
  name = "${local.name_prefix}-backend-kinesis-put"
  role = var.backend_task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
      Resource = [aws_kinesis_stream.play_events.arn]
    }]
  })
}
