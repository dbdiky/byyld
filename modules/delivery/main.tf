locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Origin Access Control - lets CloudFront read from the private S3 bucket without the bucket being public
resource "aws_cloudfront_origin_access_control" "processed" {
  name                              = "${local.name_prefix}-processed-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Public key + trusted key group used to validate CloudFront signed URLs.
# The backend signs URLs with the matching private key (stored in Secrets Manager,
# referenced by the backend's environment, not modeled here - generate the keypair out of band
# and feed the public key in via the cloudfront_public_key_pem variable in environments/*).
variable "cloudfront_public_key_pem" {
  description = "PEM-encoded public key used to validate signed URLs. Generate the keypair out of band; private key goes to the backend's secrets, public key goes here."
  type        = string
}

resource "aws_cloudfront_public_key" "signing_key" {
  name        = "${local.name_prefix}-signing-key"
  encoded_key = var.cloudfront_public_key_pem
  comment     = "Used to validate signed URLs/cookies for subscriber-gated streaming"
}

resource "aws_cloudfront_key_group" "signing" {
  name    = "${local.name_prefix}-signing-key-group"
  items   = [aws_cloudfront_public_key.signing_key.id]
  comment = "Trusted key group for subscriber-gated audio delivery"
}

resource "aws_cloudfront_distribution" "audio" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} audio delivery"
  price_class     = var.price_class

  origin {
    domain_name              = var.processed_bucket_regional_domain_name
    origin_id                = "processed-audio-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.processed.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = "processed-audio-s3"
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true

    # Every request must carry a valid signature from the backend - no public access to tracks
    trusted_key_groups = [aws_cloudfront_key_group.signing.id]

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # Replace with acm_certificate_arn + minimum_protocol_version once a custom domain is set up
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-audio-distribution"
  })
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Bucket policy allowing only this specific CloudFront distribution to read via OAC
resource "aws_s3_bucket_policy" "processed_cloudfront_access" {
  bucket = var.processed_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::${var.processed_bucket_name}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.audio.arn
        }
      }
    }]
  })
}

# The backend signs URLs/cookies using a private key counterpart to the public key above.
# That private key lives in Secrets Manager and is granted to the backend task role in
# environments/*/iam.tf, since that grant depends on both this module's output and the
# backend module's task role - wiring it here would create a cycle.
