resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_prefix = "${var.name_prefix}-${var.environment}-${random_id.suffix.hex}"
  bucket_name     = "${local.resource_prefix}-submissions"
}

data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/../lambda/jibucloud-handler.zip"
}

resource "aws_s3_bucket" "submissions" {
  bucket        = local.bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "submissions" {
  bucket                  = aws_s3_bucket.submissions.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "submissions" {
  bucket = aws_s3_bucket.submissions.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 must be configured to publish supported bucket events to EventBridge.
resource "aws_s3_bucket_notification" "eventbridge" {
  bucket      = aws_s3_bucket.submissions.id
  eventbridge = true
}

resource "aws_sns_topic" "notifications" {
  name = "${local.resource_prefix}-lecturer-notifications"
}

resource "aws_sns_topic_subscription" "lecturer_email" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sqs_queue" "submissions" {
  name                       = "${local.resource_prefix}-submission-work"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 10
}

resource "aws_iam_role" "lambda_execution" {
  name = "${local.resource_prefix}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LambdaAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${local.resource_prefix}-lambda-permissions"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteFunctionLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.resource_prefix}-processor:*"
      },
      {
        Sid    = "ConsumeSubmissionQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.submissions.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${local.resource_prefix}-processor"
  retention_in_days = 7
}

resource "aws_lambda_function" "processor" {
  function_name    = "${local.resource_prefix}-processor"
  description      = "Processes JibuCloud S3 assignment-submission events from SQS."
  role             = aws_iam_role.lambda_execution.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  timeout          = 20
  memory_size      = 128

  depends_on = [
    aws_iam_role_policy.lambda_permissions,
    aws_cloudwatch_log_group.processor
  ]
}

resource "aws_lambda_event_source_mapping" "queue_to_lambda" {
  event_source_arn                   = aws_sqs_queue.submissions.arn
  function_name                      = aws_lambda_function.processor.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
  enabled                            = true
}

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${local.resource_prefix}-s3-object-created"
  description = "Routes JibuCloud assignment uploads to notification and processing."

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.submissions.bucket]
      }
    }
  })

  depends_on = [aws_s3_bucket_notification.eventbridge]
}

resource "aws_cloudwatch_event_target" "notify_lecturer" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "NotifyLecturerViaSNS"
  arn       = aws_sns_topic.notifications.arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 5
  }

  depends_on = [aws_sns_topic_policy.allow_eventbridge]
}

resource "aws_cloudwatch_event_target" "queue_for_processing" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "QueueSubmissionForLambda"
  arn       = aws_sqs_queue.submissions.arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 5
  }

  depends_on = [aws_sqs_queue_policy.allow_eventbridge]
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublishFromJibuCloudRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.notifications.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.s3_object_created.arn
        }
      }
    }]
  })
}

resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.submissions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeSendFromJibuCloudRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.submissions.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.s3_object_created.arn
        }
      }
    }]
  })
}
