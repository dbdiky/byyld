Mirror environments/dev once dev is validated against a real AWS account.
Differences to apply: multi_az = true on the database module, larger instance_class,
desired_count/min_capacity raised, and a real ACM certificate for the ALB + CloudFront.
