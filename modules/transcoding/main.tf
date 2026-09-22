locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "transcoding" {
  name = "${local.name_prefix}-transcoding"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-transcoding-cluster"
  })
}

resource "aws_cloudwatch_log_group" "transcoding" {
  name              = "/ecs/${local.name_prefix}-transcoding"
  retention_in_days = 14
  tags              = var.tags
}

# Execution role: lets ECS pull the image and write logs
resource "aws_iam_role" "execution" {
  name = "${local.name_prefix}-transcode-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: lets the running container read raw uploads and write processed output
resource "aws_iam_role" "task" {
  name = "${local.name_prefix}-transcode-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "task_s3_access" {
  name = "${local.name_prefix}-transcode-s3-access"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.raw_uploads_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.processed_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_ecs_task_definition" "transcode" {
  family                   = "${local.name_prefix}-transcode"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "ffmpeg-transcoder"
      image     = "${var.ecr_repository_url}:latest"
      essential = true
      environment = [
        { name = "RAW_BUCKET", value = var.raw_uploads_bucket_name },
        { name = "PROCESSED_BUCKET", value = var.processed_bucket_name },
        { name = "BITRATE_VARIANTS", value = join(",", var.bitrate_variants) }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.transcoding.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "transcode"
        }
      }
    }
  ])

  tags = var.tags
}

# Lambda that fires on S3 upload and launches the Fargate transcode task via RunTask
resource "aws_iam_role" "trigger_lambda" {
  name = "${local.name_prefix}-transcode-trigger-role"

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

resource "aws_iam_role_policy_attachment" "trigger_lambda_basic" {
  role       = aws_iam_role.trigger_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "trigger_lambda_ecs" {
  name = "${local.name_prefix}-transcode-trigger-ecs-run"
  role = aws_iam_role.trigger_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = [aws_ecs_task_definition.transcode.arn]
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.execution.arn,
          aws_iam_role.task.arn
        ]
      }
    ]
  })
}

# Placeholder deployment package - replace with the real trigger code before deploying.
# This Lambda's job is small: parse the S3 event, call ecs:RunTask with the upload's S3 key
# passed in as a container override environment variable.
data "archive_file" "trigger_placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/trigger_placeholder.zip"

  source {
    content  = <<-EOF
      def handler(event, context):
          # TODO: parse event["Records"][0]["s3"], call ecs RunTask with the object key
          # passed in via containerOverrides so the FFmpeg container knows what to fetch.
          print(event)
          return {"status": "received"}
    EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "transcode_trigger" {
  function_name = "${local.name_prefix}-transcode-trigger"
  role          = aws_iam_role.trigger_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.trigger_placeholder.output_path
  source_code_hash = data.archive_file.trigger_placeholder.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER_ARN    = aws_ecs_cluster.transcoding.arn
      TASK_DEFINITION_ARN = aws_ecs_task_definition.transcode.arn
      SUBNET_IDS          = join(",", var.private_subnet_ids)
      SECURITY_GROUP_ID   = var.transcoding_security_group_id
    }
  }

  tags = var.tags
}
