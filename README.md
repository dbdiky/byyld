# Ryvyl infrastructure

Terraform for the Ryvyl fair-pay music streaming platform on AWS. Built module-first so
each piece of the architecture (networking, storage, transcoding, the API backend, CDN
delivery, and the play-event/payout pipeline) can be reasoned about, tested, and scaled
independently.

## Layout

```
modules/
  networking/      VPC, subnets, security groups - everything else lives inside this
  storage/         S3 buckets for raw uploads and processed (transcoded) audio
  database/        RDS Postgres - catalog, subscriptions, payout aggregation
  transcoding/      ECS Fargate + FFmpeg, triggered by S3 upload events
  delivery/         CloudFront in front of the processed bucket, signed URLs only
  backend/          ECS Fargate API service (auth, catalog, subscriptions, URL signing)
  data-pipeline/    Kinesis play events -> Firehose archive (S3) + Lambda aggregator (Postgres)

environments/
  dev/              Wires all modules together for the dev account/workspace
  staging/          (mirror dev once dev is validated)
  prod/             (mirror dev, with multi_az=true, larger instance sizes, PriceClass_All)
```

## Dependency order

The module graph is intentionally a DAG, not a cycle. `networking` and `storage` are roots;
`transcoding`, `database`, and `delivery` branch off those; `backend` depends on all three;
`data_pipeline` depends on `backend` last (it needs the backend's task role to grant
`kinesis:PutRecord`). The one cross-module wire that doesn't fit cleanly inside a single
module - the S3-to-Lambda notification connecting `storage`'s bucket to `transcoding`'s
Lambda - lives in `environments/dev/notifications.tf` instead, since putting it inside
either module would create a real circular dependency.

## Before you run this

A few things are referenced as variables rather than created by this code, because they're
either one-time setup or need to exist before the rest can be applied:

1. **Remote state backend.** `environments/dev/main.tf` has the S3 backend block commented
   out. Create the state bucket and DynamoDB lock table by hand (or a small bootstrap config)
   first, then uncomment.
2. **Container images.** `var.ecr_backend_repo_url` and `var.ecr_transcoder_repo_url` expect
   existing ECR repos with at least one image pushed (`:latest`). The task definitions
   reference `:latest` directly - move to immutable tags + CI-driven deploys once the app
   code exists.
3. **CloudFront signing keypair.** Generate an RSA keypair out of band (`openssl genrsa` /
   `openssl rsa -pubout`). The public key goes in `var.cloudfront_public_key_pem`. The private
   key needs to land in Secrets Manager and be readable by the backend task role - that grant
   isn't wired yet since it depends on app-side signing code being ready.
4. **Lambda source code.** Both `transcoding` and `data-pipeline` ship placeholder Lambda
   bodies (see the `archive_file` data sources marked `_placeholder`). They deploy successfully
   but only log the event - replace with real handler code before relying on them.
5. **TLS certificate.** The backend ALB listener and CloudFront distribution both default to
   AWS-provided certs. Once a domain exists, request an ACM cert and wire
   `acm_certificate_arn` into both.

## Running it

```bash
cd environments/dev
terraform init
terraform plan -var="ecr_backend_repo_url=..." \
                -var="ecr_transcoder_repo_url=..." \
                -var="cloudfront_public_key_pem=$(cat signing_key.pub)"
terraform apply
```

Consider a `dev.auto.tfvars` (gitignored) instead of repeating `-var` flags.

## Cost notes

Your own cost model (`Ryvyl Cost Calculations.xlsx`) already prices storage + CloudFront at
roughly $670/month at 5,000 GB/month bandwidth - that number doesn't include compute (Fargate
backend + transcoding) or RDS, both added by this code. Two levers worth watching as you scale:

- **Bitrate mix.** All three variants (96/160/320kbps) get produced per upload, but which one
  actually gets *served* per stream is a backend decision. Defaulting more listeners to 160kbps
  over 320kbps directly reduces CloudFront bandwidth cost - and by your own model, that's money
  that can move to the Artist Bank instead.
- **NAT gateway cost.** This config provisions one NAT gateway per AZ for resilience. For dev,
  consider dropping to a single NAT (edit `modules/networking/main.tf`) to cut idle cost - NAT
  gateways bill hourly regardless of traffic.
