variable "project" {
  type    = string
  default = "ryvyl"
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "transcoding_security_group_id" {
  type = string
}

variable "ecr_repository_url" {
  description = "ECR repo URL holding the FFmpeg transcoding container image"
  type        = string
}

variable "raw_uploads_bucket_arn" {
  type = string
}

variable "processed_bucket_arn" {
  type = string
}

variable "raw_uploads_bucket_name" {
  type = string
}

variable "processed_bucket_name" {
  type = string
}

variable "cpu" {
  description = "Fargate task vCPU (in CPU units, 1024 = 1 vCPU). Transcoding is CPU-bound."
  type        = number
  default     = 2048
}

variable "memory" {
  type    = number
  default = 4096
}

variable "bitrate_variants" {
  description = "Bitrate variants the transcoder should produce per upload, in kbps"
  type        = list(number)
  default     = [96, 160, 320]
}

variable "tags" {
  type    = map(string)
  default = {}
}
