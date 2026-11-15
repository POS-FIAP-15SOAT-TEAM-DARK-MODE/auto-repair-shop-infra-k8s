# ADR 0005 — Messaging with SNS fan-out and one SQS queue per consumer

- Status: Accepted
- Date: 2026-11-01
- Deciders: Auto Repair Shop Team
- Tags: messaging, saga, infrastructure, tech-challenge

## Context

The service order saga coordinates billing and execution asynchronously, and
the history service consumes events from several producers. The services run
on EKS and are deployed as independent workloads. The message contract is
defined in `docs/fase4/contracts/messaging.md` of the `auto-repair-shop` repo.
This ADR records the infrastructure choices behind it, implemented in
`terraform/messaging/`.

## Decision

1. **SNS topics for publication, SQS queues for consumption.** Four topics:
   `saga-commands` (commands, with a `target` attribute), `so-events`,
   `billing-events` and `execution-events`. Each consumer owns its queue
   (`billing-queue`, `execution-queue`, `catalog-queue`, `so-saga-replies`,
   `history-queue`) and subscribes to the topics it needs. This is fan-out
   without a shared queue: a message is delivered to every subscribed queue.
2. **Command routing by message attribute.** `saga-commands` delivers to three
   queues, each with a filter policy on `target` (`billing`, `execution`,
   `catalog`). A consumer never sees commands for another service, and the
   filter runs in SNS, so no consumer code is needed to discard them.
3. **Raw message delivery on every SNS→SQS subscription.** The queue body is
   the message envelope (see the contract), not the SNS wrapper. Consumers
   parse one format, and the message attributes (`target`, `type`) stay
   available for filtering.
4. **Standard queues, not FIFO.** The contract does not require ordering: the
   saga state machine validates the sequence, and it ignores out-of-order
   messages with a log entry. FIFO would add throughput limits and a
   `MessageGroupId` design for no gain here.
5. **Dead-letter queue per queue.** Each queue redrives to `<queue>-dlq` after
   `maxReceiveCount = 5`. DLQs keep messages for 14 days, the longest SQS
   retention, so failures can be inspected. Main queues keep messages for 4
   days, with a 60-second visibility timeout and 20-second long polling.
6. **Queue policies restrict senders.** Each queue accepts `sqs:SendMessage`
   only from the SNS topics that feed it, through an `aws:SourceArn` condition.
7. **Physical names** are `auto-repair-shop-<env>-<logical name>`, and
   services read URLs and ARNs from environment variables. Renaming a queue
   therefore touches only Terraform and the variable mapping.
8. **Learner Lab compatibility.** The layer creates no IAM resources, so it
   works with `manage_iam = false`. It is validated in CI against MiniStack
   (`messaging-ministack` job), which needs no AWS account.

## Consequences

### Positive

- Adding a consumer means adding a queue and a subscription, with no change
  to publishers.
- Poison messages leave the main flow after five attempts and wait in a DLQ.
- The CI job catches topology regressions (topic, queue and subscription
  counts) without credentials.

### Negative

- Standard queues are at-least-once and unordered. Consumers must dedupe on
  `message_id` and tolerate reordering, which the contract already requires.
- The publisher side needs a transactional outbox to make "state changed and
  message published" atomic. That is outside this layer and is required by the
  contract.
- `aws_sqs_queue_policy` lists the topics that feed each queue. Adding a
  publisher to an existing queue means editing `locals.tf` in this repo.

## Alternatives considered

- **A. Direct SQS queues per service, with no SNS.** Each publisher would send
  to every consumer's queue, so publishers would need to know their consumers.
  Fan-out and filtering would move into application code. Rejected.
- **B. EventBridge.** Also supports filtering and fan-out, with richer routing
  rules. Rejected to keep the infrastructure in the SNS/SQS set the course
  covers and that MiniStack emulates for the CI check.
- **C. One shared queue with consumer-side filtering.** Simplest topology, but
  every consumer would receive and discard messages it does not handle, and
  DLQ handling would be shared. Rejected.
- **D. FIFO topics and queues.** Ordering per saga, at the cost of lower
  throughput and a different consumer design. Rejected: ordering is handled by
  the saga state machine.
