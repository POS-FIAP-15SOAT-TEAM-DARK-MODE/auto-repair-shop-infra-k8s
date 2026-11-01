# ADR 0007 — Node credentials reachable from pods (IMDS hop limit 2)

- Status: Accepted (known risk)
- Deciders: Auto Repair Shop Team
- Related: [ADR 0005](0005-messaging-with-sns-sqs.md), `terraform/aws/eks.tf`

## Context

The services that talk to SNS, SQS and DynamoDB (Catalog, Billing, Execution, History and Service Order) need AWS credentials. The project runs on an AWS Academy Learner Lab, which forbids creating IAM roles and OIDC providers (`manage_iam = false`). IAM Roles for Service Accounts (IRSA) is therefore not available, and the only credentials a pod can obtain are the ones of the **node role** (`LabRole`), read from the instance metadata service (IMDS).

A pod reaches IMDS only if the IMDSv2 hop limit is at least 2, because the pod network adds a hop. `terraform/aws/eks.tf` sets `http_put_response_hop_limit = 2` on the node group.

## Decision

Keep hop limit 2 and the node role as the credential source in the Lab. IMDSv2 stays mandatory (`http_tokens = "required"`).

## Risk

With hop limit 2, **any pod on a node can obtain the node role's credentials**, not only the pods that need AWS. A server-side request forgery (SSRF) flaw in any service would let an attacker read them. Mitigating factors today:

- The only internet-facing pod is the gateway, a reverse proxy that forwards to fixed upstreams from configuration and never fetches a URL chosen by the caller.
- No service fetches a caller-supplied URL. This changes the day a webhook receiver or an outbound integration (for example a payment provider) is added, and this ADR must then be revisited.
- The Customer service and the gateway need no AWS credentials at all.

## Mitigations (not applied yet)

1. **NetworkPolicy:** deny egress to `169.254.169.254/32` for the pods that need no AWS access (gateway and Customer first). This works only if the cluster network plugin enforces `NetworkPolicy`; the default Amazon VPC CNI does not unless network policy support is enabled on the add-on. Whether the Learner Lab allows enabling it is **unverified**.
2. **Account with IAM rights:** use IRSA, one role per service with least privilege, and set the hop limit back to 1. `manage_iam = true` already creates the OIDC provider in this repository.
3. **Scope the node role:** in an account where the role can be chosen, grant it only the SNS, SQS and DynamoDB actions the services use.

## Consequences

- The Lab deployment works with no credential management inside the cluster.
- The credentials of the node role are one SSRF away from any pod, until mitigation 1 or 2 is applied.
- Any new feature that makes a service fetch a caller-supplied URL needs a security review first.
