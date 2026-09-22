variable "project" {
  type    = string
  default = "ryvyl"
}

variable "environment" {
  type = string
}

variable "processed_bucket_name" {
  type = string
}

variable "processed_bucket_regional_domain_name" {
  type = string
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US/EU/Canada only (cheapest), PriceClass_All = global edge coverage."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  type    = map(string)
  default = {}
}
