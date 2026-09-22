locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Raw uploads bucket: artists PUT directly here via presigned URLs.
# Short lifecycle - once transcoding succeeds we don't need to keep the original around long-term
# (but keep it for a window in case a transcode job needs to be retried).
resource "aws_s3_bucket" "raw_uploads" {
  bucket = "${local.name_prefix}-raw-uploads"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-raw-uploads"
  })
}

resource "aws_s3_bucket_versioning" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  rule {
    id     = "expire-after-transcode-window"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_uploads" {
  bucket                  = aws_s3_bucket.raw_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  cors_rule {
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"] # Tighten to the actual app domain(s) once known
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# Processed bucket: streaming-ready bitrate variants (96/160/320kbps). This is what CloudFront fronts.
resource "aws_s3_bucket" "processed" {
  bucket = "${local.name_prefix}-processed-audio"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-processed-audio"
  })
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "intelligent-tiering-cold-catalog"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# Note: the S3 -> Lambda event notification that triggers transcoding is NOT wired here.
# Storage only creates buckets; the notification lives in environments/*/notifications.tf
# as a standalone resource, since it depends on both this module's bucket and the
# transcoding module's Lambda, and wiring it inside either module would create a cycle.
