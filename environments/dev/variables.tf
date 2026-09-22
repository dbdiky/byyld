variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "ecr_backend_repo_url" {
  description = "ECR repo URL for the API backend image - create the repo and push an image before applying"
  type        = string
}

variable "ecr_transcoder_repo_url" {
  description = "ECR repo URL for the FFmpeg transcoder image"
  type        = string
}

variable "cloudfront_public_key_pem" {
  description = "PEM-encoded public key for validating CloudFront signed URLs"
  type        = string
}
