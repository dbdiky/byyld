# This wiring depends on both module.storage (the bucket) and module.transcoding (the Lambda),
# so it lives at the environment level rather than inside either module - that's what keeps
# the module dependency graph a clean DAG instead of a cycle.

resource "aws_lambda_permission" "allow_s3_invoke_transcode_trigger" {
  statement_id  = "AllowS3InvokeTranscodeTrigger"
  action        = "lambda:InvokeFunction"
  function_name = module.transcoding.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.storage.raw_uploads_bucket_arn
}

resource "aws_s3_bucket_notification" "raw_upload_trigger" {
  bucket = module.storage.raw_uploads_bucket_name

  lambda_function {
    lambda_function_arn = module.transcoding.lambda_function_arn
    events               = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_transcode_trigger]
}
