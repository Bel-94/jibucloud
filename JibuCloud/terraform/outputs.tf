output "submission_bucket_name" {
  description = "Upload workshop assignment files to this bucket."
  value       = aws_s3_bucket.submissions.bucket
}

output "submission_bucket_arn" {
  value = aws_s3_bucket.submissions.arn
}

output "eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.s3_object_created.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.notifications.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.submissions.id
}

output "lambda_function_name" {
  value = aws_lambda_function.processor.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.processor.name
}

output "region" {
  value = var.aws_region
}
