output "topic_arns" {
  description = "Logical topic name -> SNS topic ARN"
  value       = { for k, t in aws_sns_topic.this : k => t.arn }
}

output "queue_urls" {
  description = "Logical queue name -> SQS queue URL"
  value       = { for k, q in aws_sqs_queue.this : k => q.url }
}

output "queue_arns" {
  description = "Logical queue name -> SQS queue ARN"
  value       = { for k, q in aws_sqs_queue.this : k => q.arn }
}

output "dlq_arns" {
  description = "Logical queue name -> dead-letter queue ARN"
  value       = { for k, q in aws_sqs_queue.dlq : k => q.arn }
}
