variable "project" {
  type    = string
  default = "ryvyl"
}

variable "environment" {
  type = string
}

variable "shard_count" {
  description = "Kinesis shard count. Each shard handles up to 1000 records/sec or 1MB/sec write. Start at 1-2 and scale with subscriber growth."
  type        = number
  default     = 2
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "backend_security_group_id" {
  description = "Lambda consumer runs in the same network context to reach RDS"
  type        = string
}

variable "db_secret_arn" {
  type = string
}

variable "backend_task_role_id" {
  description = "Backend task role, granted kinesis:PutRecord so the API can emit play events"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
