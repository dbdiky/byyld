terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state - create this S3 bucket + DynamoDB lock table once, by hand or via a
  # bootstrap config, before running this environment. Uncomment once it exists.
  # backend "s3" {
  #   bucket         = "ryvyl-terraform-state"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "ryvyl-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ryvyl"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
