locals {
  # Same convention as the other per-environment states: the workspace is the
  # environment, and "default" maps to stg so validate/plan work before a
  # workspace is selected.
  environment = terraform.workspace == "default" ? "stg" : terraform.workspace

  # Physical names are "<project>-<env>-<logical name>" (see docs/fase4
  # contracts/resources.md). The services never build names: they read the
  # URLs/ARNs from environment variables.
  prefix = "${var.project}-${local.environment}-"

  tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }

  topics = toset(["saga-commands", "so-events", "billing-events", "execution-events"])

  queues = toset(["billing-queue", "execution-queue", "catalog-queue", "so-saga-replies", "history-queue"])

  # One entry per SNS -> SQS subscription. `target` is matched against the
  # `target` message attribute; null means no filter policy.
  subscriptions = [
    { queue = "billing-queue", topic = "saga-commands", target = "billing" },
    { queue = "execution-queue", topic = "saga-commands", target = "execution" },
    { queue = "catalog-queue", topic = "saga-commands", target = "catalog" },
    { queue = "so-saga-replies", topic = "billing-events", target = null },
    { queue = "so-saga-replies", topic = "execution-events", target = null },
    { queue = "history-queue", topic = "so-events", target = null },
    { queue = "history-queue", topic = "billing-events", target = null },
    { queue = "history-queue", topic = "execution-events", target = null },
  ]

  # Topics that feed each queue, used by the queue policies.
  queue_topics = {
    for q in local.queues : q => distinct([for s in local.subscriptions : s.topic if s.queue == q])
  }
}
