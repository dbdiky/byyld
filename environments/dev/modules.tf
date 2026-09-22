locals {
  environment = "dev"
  tags = {
    Project     = "ryvyl"
    Environment = local.environment
  }
}

# 1. Networking - everything else lives inside this VPC
module "networking" {
  source = "../../modules/networking"

  environment          = local.environment
  azs                  = var.azs
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  tags                 = local.tags
}

# 2. Storage - just the S3 buckets, no Lambda wiring yet (avoids a cycle with transcoding)
module "storage" {
  source = "../../modules/storage"

  environment = local.environment
  tags        = local.tags
}

# 3. Database - independent of storage/transcoding, only needs networking
module "database" {
  source = "../../modules/database"

  environment                = local.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  instance_class              = "db.t4g.medium" # dev-sized; bump for staging/prod
  multi_az                    = false
  tags                         = local.tags
}

# 4. Transcoding - needs storage's bucket ARNs (read raw, write processed)
module "transcoding" {
  source = "../../modules/transcoding"

  environment                   = local.environment
  vpc_id                         = module.networking.vpc_id
  private_subnet_ids             = module.networking.private_subnet_ids
  transcoding_security_group_id  = module.networking.transcoding_security_group_id
  ecr_repository_url              = var.ecr_transcoder_repo_url
  raw_uploads_bucket_arn          = module.storage.raw_uploads_bucket_arn
  processed_bucket_arn            = module.storage.processed_bucket_arn
  raw_uploads_bucket_name         = module.storage.raw_uploads_bucket_name
  processed_bucket_name           = module.storage.processed_bucket_name
  bitrate_variants                 = [96, 160, 320]
  tags                              = local.tags
}

# 5. Delivery - needs storage's processed bucket; does NOT need the backend (no cycle)
module "delivery" {
  source = "../../modules/delivery"

  environment                          = local.environment
  processed_bucket_name                 = module.storage.processed_bucket_name
  processed_bucket_regional_domain_name = module.storage.processed_bucket_regional_domain_name
  cloudfront_public_key_pem              = var.cloudfront_public_key_pem
  price_class                             = "PriceClass_100" # widen to PriceClass_All post-Kickstarter if listeners are global
  tags                                     = local.tags
}

# 6. Backend - needs database, storage bucket names, and delivery's CloudFront domain
module "backend" {
  source = "../../modules/backend"

  environment                = local.environment
  vpc_id                      = module.networking.vpc_id
  public_subnet_ids           = module.networking.public_subnet_ids
  private_subnet_ids          = module.networking.private_subnet_ids
  backend_security_group_id   = module.networking.backend_security_group_id
  alb_security_group_id       = module.networking.alb_security_group_id
  ecr_repository_url            = var.ecr_backend_repo_url
  db_secret_arn                 = module.database.secret_arn
  min_capacity                   = 2
  max_capacity                   = 20
  environment_variables = {
    DB_ENDPOINT             = module.database.db_endpoint
    DB_NAME                  = module.database.db_name
    RAW_UPLOADS_BUCKET       = module.storage.raw_uploads_bucket_name
    PROCESSED_BUCKET         = module.storage.processed_bucket_name
    CLOUDFRONT_DOMAIN        = module.delivery.distribution_domain_name
    CLOUDFRONT_KEY_GROUP_ID  = module.delivery.signing_key_group_id
  }
  tags = local.tags
}

# 7. Data pipeline - needs database and the backend's task role (to grant kinesis:PutRecord)
module "data_pipeline" {
  source = "../../modules/data-pipeline"

  environment                = local.environment
  shard_count                  = 2
  vpc_id                        = module.networking.vpc_id
  private_subnet_ids            = module.networking.private_subnet_ids
  backend_security_group_id     = module.networking.backend_security_group_id
  db_secret_arn                  = module.database.secret_arn
  backend_task_role_id           = module.backend.task_role_id
  tags                             = local.tags
}
