# --- Topics (SNS) ------------------------------------------------------------

resource "aws_sns_topic" "this" {
  for_each = local.topics

  name = "${local.prefix}${each.key}"
  tags = local.tags
}

# --- Queues (SQS, Standard) and their dead-letter queues ----------------------

resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${local.prefix}${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days
  tags                      = local.tags
}

resource "aws_sqs_queue" "this" {
  for_each = local.queues

  name                       = "${local.prefix}${each.key}"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 5
  })

  tags = local.tags
}

# Only the topics that feed a queue may send to it.
resource "aws_sqs_queue_policy" "this" {
  for_each = local.queues

  queue_url = aws_sqs_queue.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSnsPublish"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.this[each.key].arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = [for t in local.queue_topics[each.key] : aws_sns_topic.this[t].arn]
        }
      }
    }]
  })
}

# --- Subscriptions (SNS -> SQS) ----------------------------------------------

# Raw message delivery: the queue body is the message envelope itself, without
# the SNS wrapper. Commands are filtered on the `target` message attribute.
resource "aws_sns_topic_subscription" "this" {
  for_each = { for s in local.subscriptions : "${s.queue}:${s.topic}" => s }

  topic_arn            = aws_sns_topic.this[each.value.topic].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this[each.value.queue].arn
  raw_message_delivery = true

  filter_policy       = each.value.target == null ? null : jsonencode({ target = [each.value.target] })
  filter_policy_scope = each.value.target == null ? null : "MessageAttributes"

  depends_on = [aws_sqs_queue_policy.this]
}
