# auto-repair-shop-infra-k8s

Terraform for the Kubernetes cluster (AWS EKS) that runs the
[auto-repair-shop](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop)
application, plus the shared bootstrap (remote state bucket, ECR, GitHub OIDC)
and cluster add-ons. This repository was split out of the app's monorepo as
part of a move to independently deployable services, each with its own
CI/CD.

> Managed database (RDS) lives in the sibling
> [auto-repair-shop-infra-db](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-infra-db)
> repository — it reads the VPC/network outputs from this repo's `aws` state
> via `terraform_remote_state`.

## Technologies

- Terraform (>= 1.10), AWS provider (~> 6.0)
- AWS: VPC, EKS, ECR, IAM (OIDC for GitHub Actions), Secrets Manager access
  (via the `addons` state's External Secrets Operator IRSA role)
- Helm (via the `addons` state): AWS Load Balancer Controller, metrics-server,
  External Secrets Operator, kube-prometheus-stack (Prometheus + Grafana)
- GitHub Actions (OIDC — no long-lived AWS keys after bootstrap)

## Structure — 5 independent Terraform states

| State | Provisions | Cadence |
|---|---|---|
| `terraform/bootstrap/` | S3 bucket for remote tfstate (versioned, encrypted, native locking) — shared with `auto-repair-shop-infra-db` | run once |
| `terraform/shared/` | ECR (app image repo) · GitHub OIDC provider · IAM roles (`deploy-stg/prd`, `terraform`) | run once |
| `terraform/aws/` | VPC · EKS (per Terraform workspace `stg`/`prd`) | per environment |
| `terraform/addons/` | Helm add-ons: ALB Controller · metrics-server · External Secrets (+ IRSA) · kube-prometheus-stack | per environment |
| `terraform/gateway/` | AWS API Gateway (HTTP API): routes `/auth/customer-login` to the lambda in `auto-repair-shop-lambda-auth`, everything else to the app | per environment |

```
terraform/
├── bootstrap/   # S3 state bucket (run once)
├── shared/      # ECR + GitHub OIDC + IAM roles (run once)
├── aws/         # VPC, EKS per env (workspaces: stg | prd)
├── addons/      # ALB controller + metrics-server + External Secrets + kube-prometheus-stack (per env)
└── gateway/     # API Gateway: routes to the lambda + the app (per env)
```

## Deploy — driven from GitHub Actions

No AWS tooling is needed on your machine; all infra is applied by GitHub
Actions via OIDC (or static keys only for the one-time bootstrap step).

**One-time bootstrap:**
1. Set `github_repo` in `terraform/shared/variables.tf` to
   `POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-infra-k8s` (or the owning
   org/repo, if different).
2. Add repo secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (an admin
   user) — or the AWS Academy Learner Lab triple
   (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`).
3. Run the **Infra bootstrap (one-time)** workflow — creates the state
   bucket, the GitHub OIDC provider, the IAM roles and ECR, and prints the
   outputs.
4. Remove the static AWS key secrets — everything after this uses OIDC
   (unless on a restricted/Lab account, see below).

**GitHub config** (Settings → Environments):
- `infra` → variable `AWS_TERRAFORM_ROLE_ARN` = shared output
  `terraform_role_arn` (add required reviewers to gate infra applies).

**Provision the cluster** — run the **Infra (Terraform)** workflow
(`workflow_dispatch`) with `action=apply` for each: `aws` stg, `aws` prd,
`addons` stg, `addons` prd. Copy the printed `cluster_name` into the
`auto-repair-shop` app repo's `EKS_CLUSTER_NAME` GitHub Environment variable
(STG/PRD), and share the same value with `auto-repair-shop-infra-db` if it
needs it.

**Provision the API Gateway** (`gateway` layer, after both of these have
already run at least once):
1. `auto-repair-shop-lambda-auth` deployed (its `function_arn` is read here
   via `terraform_remote_state`).
2. `auto-repair-shop`'s `Docker` workflow deployed the app at least once.
   Its deploy job publishes the app's public LoadBalancer hostname to SSM
   parameter `/auto-repair-shop/<env>/app-backend-host` as its last step —
   this state reads that automatically via a data source, no manual
   variable to set (the ELB itself is Kubernetes-created, not
   Terraform-managed, so this SSM parameter is the handoff point between
   the two control planes).

Then run **Infra (Terraform)** with `layer=gateway`, `environment=stg`,
`action=apply`. Output `api_endpoint` is the public base URL —
`POST {api_endpoint}/auth/customer-login` for a token, everything else
proxies straight through to the app. Re-running `apply` after any app
redeploy picks up a new ELB hostname automatically, next time the SSM
parameter changes.

> **Last tested live endpoint** (`stg`, AWS Academy Learner Lab — tears
> down when the Lab session ends, so treat this as a point-in-time
> reference, not a standing URL):
> `https://f3ssj59u99.execute-api.us-east-1.amazonaws.com/stg`

PRs touching `terraform/**` get an automatic `fmt` + `validate` (no
credentials required).

### Restricted accounts (AWS Academy Learner Lab)

Learner Lab accounts forbid creating IAM roles / OIDC providers, so the stack
runs in a degraded mode, auto-detected at runtime from
`aws sts get-caller-identity` (a `voclabs`/`LabRole` caller ⇒
`manage_iam=false`, reusing `LabRole` for the EKS cluster and nodes; no OIDC
provider, deploy/terraform roles or IRSA are created — so the ALB Controller
and External Secrets add-ons are skipped). Override with the `AWS_AUTH_MODE`,
`MANAGE_IAM`, `EXECUTION_ROLE_ARN` repo variables if needed.

## Step-by-step walkthrough (AWS Academy Learner Lab)

A concrete, click-by-click version of the "Deploy" section above, for anyone
running this on a Learner Lab account for the first time.

1. **Get Lab credentials.** In your AWS Academy course, open the Learner Lab,
   click **Start Lab**, wait for the status dot to turn green, then click
   **AWS Details → AWS CLI: Show**. Copy the three values
   (`aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`).
   These expire when the lab session ends or times out — re-fetch them any
   time a workflow run fails on an auth step.

2. **Add them as repo secrets**, not variables (repo-level, not an
   environment): this repo → **Settings → Secrets and variables → Actions →
   Secrets → New repository secret**, three times:
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`.

3. **Run bootstrap.** Actions tab → **"Infra bootstrap (one-time)"** → Run
   workflow (branch: this feature branch, until merged) → Run workflow. This
   creates the state bucket and, since Learner Lab forbids IAM/OIDC writes,
   `shared` auto-runs in degraded mode: only the ECR repo gets created (no
   `terraform_role_arn`, so skip the `infra` Environment/`AWS_TERRAFORM_ROLE_ARN`
   setup entirely — every later apply just reuses the same static secrets).

4. **Provision the cluster.** Actions tab → **"Infra (Terraform)"** → Run
   workflow → `layer=aws`, `environment=stg`, `action=plan` first to sanity
   check, then re-run with `action=apply`. Takes ~10-15 minutes (EKS control
   plane + node group). This same run auto-chains into applying `addons`
   afterward — expect the IRSA-dependent pieces (ALB Controller, External
   Secrets) to be skipped/degraded, since there's no OIDC provider in Lab mode.

5. **Grab the output.** Expand the "Show outputs" step, copy `cluster_name`
   (e.g. `auto-repair-shop-stg-eks`) — you'll need it in `auto-repair-shop-infra-db`
   and in the app repo.

6. Continue in `auto-repair-shop-infra-db`'s README for the database, then the
   `auto-repair-shop` app repo's `Docker` workflow to actually ship the app.

**Inspecting the live cluster from your machine** (optional, useful for
debugging): install `awscli` + `kubectl` locally, `aws configure` with the
same Lab triple, then:
```bash
aws eks update-kubeconfig --region us-east-1 --name auto-repair-shop-stg-eks
kubectl -n auto-repair-shop get pods
kubectl -n auto-repair-shop logs <pod-name>
```

## Observability — CPU/memory metrics & dashboards

The `addons` state installs
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
(Prometheus + Grafana + node-exporter + kube-state-metrics) into the
`monitoring` namespace. It needs no AWS permissions, so it runs the same way
on Learner Lab accounts. Persistence is disabled (no EBS CSI driver is
installed here) — Prometheus keeps 6h of retention in-memory/ephemeral
storage, enough for live dashboards, not for long-term history.

Node/pod CPU and memory come from node-exporter + kube-state-metrics, and
Grafana ships with the chart's default dashboards already provisioned — no
manual dashboard building needed, e.g. **Kubernetes / Compute Resources /
Cluster** and **Node Exporter / Nodes** cover cluster- and node-level CPU out
of the box.

**Access Grafana** — exposed via a plain `LoadBalancer` Service (same
mechanism the app uses in Lab mode, no ALB Controller/IRSA needed), so it has
a real URL instead of requiring `kubectl port-forward`:
```bash
kubectl -n monitoring get svc kube-prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
Open that hostname in a browser — login `admin` / `admin`. This fixed login
and public exposure are only acceptable because this is a short-lived Lab
environment for study purposes — swap for a generated secret + restricted
access before any longer-lived deployment.

**Application metrics**: the `auto-repair-shop` app repo ships a `/metrics`
endpoint and a `ServiceMonitor` in its `k8s/manifests/base`. Prometheus here
is configured to pick up *any* ServiceMonitor in the cluster
(`serviceMonitorSelectorNilUsesHelmValues = false`), so no extra wiring is
needed on this side once the app is deployed.

A dashboard for those metrics — **"Auto Repair Shop — App Metrics"** —
is provisioned automatically (`terraform/addons/dashboards.tf` +
`dashboards/app-metrics.json`, loaded via a labeled ConfigMap, same mechanism
as the chart's built-in dashboards): request rate/latency by route, 5xx rate,
service orders created, notification failures, status-transition volume and
average time to reach each status.

**Logs**: `loki-stack` (Loki + Promtail) is also installed into `monitoring`
and wired as a Loki datasource on the same Grafana — use the **Explore** tab
to query container logs (filter by `request_id` to follow one request across
the app's structured JSON logs). No persistence, same short-lived-Lab
reasoning as everything else here.

Control-plane component scraping (`kubeControllerManager`/`kubeScheduler`/
`kubeEtcd`/`kubeProxy`) and Alertmanager are disabled: on managed EKS the
control-plane endpoints aren't reachable, and alerting wasn't part of this
requirement — both can be turned back on later in `terraform/addons/helm.tf`
if the team wants them.

## Tear down

Run the **Infra (Terraform)** workflow with `action=destroy`, in this order:
`addons` → `aws` (leave `shared`/`bootstrap` alone — they hold the state
bucket, ECR and IAM roles meant to be reused across environment
recreations).

The `addons` state includes a destroy-time cleanup
(`terraform/addons/cleanup.tf`) that deletes every `LoadBalancer`-type
Kubernetes Service in the cluster — **including ones this state doesn't
manage**, like the app's own Service (created by `kubectl apply` in
`auto-repair-shop`'s `docker.yml`, entirely outside any Terraform state).
Without this, that Service's backing AWS ELB is invisible to Terraform, and
destroying the `aws` layer's VPC hangs forever on
`aws_subnet`/`aws_internet_gateway`: "Still destroying..." — AWS refuses to
delete a subnet or IGW with an ENI still attached to it. Always destroy
`addons` (and let this cleanup run) **before** `aws`.

## Local development

There is no local/Kind path in this repository — the Kind-based full local
Kubernetes environment (build the app image, deploy the workload, HPA, etc.)
lives in the `auto-repair-shop` app repo (`make k8s-up`), since it only needs
Docker and never touches AWS or this Terraform.

For ad hoc `terraform plan`/`kubectl` against a real AWS cluster, install
`terraform`, `kubectl` and the `aws` CLI locally, or reuse the app repo's
toolbox container.

## Swagger / Postman

Not applicable — this repository provisions infrastructure only, no HTTP API
of its own.

## Architecture

```mermaid
flowchart TB
    client([HTTP client])
    gha["GitHub Actions (this repo)"]

    subgraph aws["AWS account"]
        iam["IAM roles"]
        ecr["ECR<br/>app images"]
        gw["API Gateway (HTTP API)<br/>terraform/gateway"]
        lambda["customer-login lambda<br/>(auto-repair-shop-lambda-auth)"]

        subgraph vpc["VPC"]
            subgraph pub["public subnets"]
                igw["IGW / NAT"]
                elb["public ELB<br/>(app's LoadBalancer Service)"]
            end
            subgraph priv["private subnets"]
                eks["EKS managed node group<br/>app pods"]
            end
            elb --> eks
        end

        ecr -.image pull.-> eks
    end

    rds[("RDS PostgreSQL<br/>provisioned by auto-repair-shop-infra-db<br/>in the same VPC")]
    eks -->|":5432 · SG: EKS nodes only"| rds

    client -->|"POST /auth/customer-login"| gw
    client -->|"everything else"| gw
    gw -->|"AWS_PROXY integration"| lambda
    gw -->|"HTTP_PROXY integration<br/>(public ELB, no VPC Link)"| elb

    gha -->|"OIDC (no static keys)"| iam
```

Time-ordered view of the same system — the CPF login through the gateway
and lambda, and how the resulting token gets used later at service-order
approval: [docs/diagrams/authentication-and-service-order-sequence.md](docs/diagrams/authentication-and-service-order-sequence.md).

## Known issue: seed race on first deploy

On a fresh app deploy, the `auto-repair-shop` pod can boot and run its DB
seed **before** the `db-migrate` Job has finished creating the schema
(nothing here gates the app Deployment's startup on the migrate Job
completing). The seed then fails with a Postgres `42P01` ("relation does not
exist") error that's only logged, never retried — the pod keeps running with
zero seed data. Symptom: seeded logins (`attendant@autorepairshop.com` etc.)
return `401` even though the deploy looked fully green.

**Workaround:** `kubectl -n auto-repair-shop rollout restart deployment/auto-repair-shop`
once migrations have completed — the app re-seeds successfully on the next boot.

**Real fix** (tracked as a follow-up, lives in the `auto-repair-shop` app
repo): add an `initContainer` to the app Deployment that waits for the
migrate Job to complete, or make `RunSeed`'s failure retry/crash-loop instead
of silently discarding the error.

## Related repositories

- [auto-repair-shop](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop) — the application deployed onto this cluster; the `gateway` state proxies to its public LoadBalancer
- [auto-repair-shop-infra-db](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-infra-db) — managed PostgreSQL, reads this repo's network outputs
- [auto-repair-shop-lambda-auth](https://github.com/POS-FIAP-15SOAT-TEAM-DARK-MODE/auto-repair-shop-lambda-auth) — the customer-login lambda; the `gateway` state reads its `function_arn` and routes `/auth/customer-login` to it
