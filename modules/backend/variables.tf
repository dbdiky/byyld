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

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "backend_security_group_id" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "ecr_repository_url" {
  description = "ECR repo URL holding the API backend container image"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}

variable "desired_count" {
  description = "Baseline number of running tasks. Autoscaling adjusts this between min/max."
  type        = number
  default     = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  description = "Upper bound for autoscaling - set generously since the brief calls for scaling fast post-Kickstarter"
  type        = number
  default     = 20
}

variable "db_secret_arn" {
  type = string
}

variable "environment_variables" {
  description = "Extra environment variables for the backend container (DB endpoint, bucket names, CloudFront key group, etc.)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
