resource "aws_kms_key" "cognito_events" {
  description             = "This key is used to encrypt congito security intelligence events"
  deletion_window_in_days = 10
}
resource "aws_s3_bucket_server_side_encryption_configuration" "log_extension" {
  bucket = aws_s3_bucket.log_extension.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cognito_events.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
resource "aws_s3_bucket" "log_extension" {
  bucket = "${local.name}-log-extension"
  # force_destroy = true
  tags = var.global_tags
}

resource "aws_s3_bucket_ownership_controls" "log_extension" {
  bucket = aws_s3_bucket.log_extension.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "log_extension" {
  depends_on = [aws_s3_bucket_ownership_controls.log_extension]

  bucket = aws_s3_bucket.log_extension.id
  acl    = "log-delivery-write"
}
resource "aws_sqs_queue" "queue_deadletter" {
  name                              = "${local.name}-dlq"
  delay_seconds                     = var.delay_seconds
  max_message_size                  = var.max_message_size
  message_retention_seconds         = var.message_retention_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  kms_master_key_id                 = aws_kms_key.cognito_events.arn
  kms_data_key_reuse_period_seconds = 300
  tags                              = var.global_tags

}

resource "aws_sqs_queue" "queue" {
  name                       = local.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.queue_deadletter.arn
    maxReceiveCount     = var.max_receive_count
  })

  kms_master_key_id                 = aws_kms_key.cognito_events.arn
  kms_data_key_reuse_period_seconds = 300
  tags                              = var.global_tags

}

data "aws_iam_policy_document" "queue_policy" {
  statement {
    sid    = "cognitopolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage"
    ]
    resources = [aws_sqs_queue.queue.arn]

  }
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.queue.id
  policy    = data.aws_iam_policy_document.queue_policy.json

}



resource "aws_iam_role" "lambda_role" {
  name = "${local.name}-lambda-role"
  tags = var.global_tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
      },
    ],
  })

  inline_policy {
    name = "${local.name}-lambda-policy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "sqs:GetQueueAttributes",
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
          ],
          Effect   = "Allow",
          Resource = aws_sqs_queue.queue.arn,
        },
        {
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ],
          Effect   = "Allow",
          Resource = "arn:aws:s3:::${aws_s3_bucket.log_extension.bucket}/*",
        },
        {
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "s3:ListBucket",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:PutObject"
          ],
          Effect   = "Allow",
          Resource = "*",
        }
      ],
    })
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

}

data "archive_file" "code" {
  type             = "zip"
  output_file_mode = "0666"
  source_dir       = "${path.module}/code/"
  output_path      = "${path.module}/code.zip"
}

resource "aws_lambda_function" "cognito_auth_events" {
  function_name                  = "${local.name}-processor"
  handler                        = "cognito_auth_func.lambda_handler"
  runtime                        = "python3.8"
  timeout                        = 100
  memory_size                    = 128
  reserved_concurrent_executions = 10

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.log_extension.bucket
      COGNITO_POOL   = var.cognito_pool
    }
  }
  layers = [aws_lambda_layer_version.cognito_auth_events.arn]

  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.code.output_path
  source_code_hash = filebase64sha256(data.archive_file.code.output_path)

  tags = var.global_tags

}

resource "aws_lambda_function_event_invoke_config" "cognito_auth_events" {
  function_name                = aws_lambda_function.cognito_auth_events.function_name
  qualifier                    = "$LATEST"
  maximum_event_age_in_seconds = 21600
  maximum_retry_attempts       = 0
}
resource "aws_lambda_layer_version" "cognito_auth_events" {
  layer_name          = local.name
  filename            = "${path.module}/files/S3LogExtensionsLayer.zip"
  compatible_runtimes = ["python3.8"]
  license_info        = "Available under the MIT-0 license"
}


resource "aws_lambda_event_source_mapping" "mapping" {
  batch_size       = 10
  event_source_arn = aws_sqs_queue.queue.arn
  function_name    = aws_lambda_function.cognito_auth_events.function_name
}

resource "aws_cloudwatch_event_rule" "events" {
  name        = "${local.name}-cloudtrail-events"
  description = "Rule to capture all CloudTrail events"
  tags        = var.global_tags
  event_pattern = jsonencode({
    source = ["aws.cognito-idp"],
    detail-type = [
      "AWS API Call via CloudTrail"
    ],
    detail = {
      eventSource = ["cognito-idp.amazonaws.com"],
      eventName   = ["InitiateAuth"]
    }
  })
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.events.name
  target_id = "${local.name}-sqs-target"
  arn       = aws_sqs_queue.queue.arn
}

resource "aws_cloudwatch_query_definition" "compromised_credentials" {
  name = "compromised_credentials"

  log_group_names = [
    "loggroupname"
  ]

  query_string = <<EOF
fields @message
| filter @message like /INFO/
| filter AuthEvents.0.EventType like "SignIn"
| filter AuthEvents.0.EventRisk.RiskDecision like "AccountTakeover" and AuthEvents.0.EventRisk.CompromisedCredentialsDetected =! "false"
| stats count(*) as RequestsperIP by AuthEvents.0.EventContextData.IpAddress as IP
| sort desc
| limit 10
EOF
}




resource "aws_cloudwatch_query_definition" "risk_level_high" {
  name = "risk_level_high"

  log_group_names = [
    "loggroupname"
  ]

  query_string = <<EOF
fields @message
| filter @message like /INFO/
| filter AuthEvents.0.EventRisk.RiskLevel like "High"
| stats count(*) as RequestsperIP by AuthEvents.0.EventContextData.IpAddress as IP, AuthEvents.0.EventType as EventType
| sort desc
| limit 10
EOF
}

resource "aws_cloudwatch_query_definition" "risk_level_context" {
  name = "risk_level_context"

  log_group_names = [
    "loggroupname"
  ]

  query_string = <<EOF
fields @message
| filter @message like /INFO/
| filter AuthEvents.0.EventRisk.RiskLevel like "High"
|stats count(*) as RequestsperCountry by AuthEvents.0.EventContextData.Country as Country
| sort desc
EOF
}