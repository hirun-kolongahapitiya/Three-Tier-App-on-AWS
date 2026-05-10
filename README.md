# Three-Tier App on AWS - Terraform + ECS Fargate + RDS

A production-style three-tier application deployed to AWS with Terraform.

## Architecture

```
        Internet
            │
            ▼
   ┌─────────────────┐
   │  Application    │  ← public subnets (2 AZs)
   │  Load Balancer  │
   └────────┬────────┘
            │
            ▼
   ┌─────────────────┐
   │  ECS Fargate    │  ← private "app" subnets
   │  (Node.js API)  │     auto-scaled 2-6 tasks
   └────────┬────────┘
            │
            ▼
   ┌─────────────────┐
   │  RDS Postgres   │  ← private "data" subnets
   │  (no internet)  │     no internet route
   └─────────────────┘

   ┌──────────────┐    ┌────────────────┐    ┌──────────────┐
   │  S3 (assets) │    │ CloudWatch     │    │ Secrets      │
   │              │    │ logs + alarms  │    │ Manager (DB) │
   └──────────────┘    └────────┬───────┘    └──────────────┘
                                │
                                ▼
                          ┌─────────┐
                          │   SNS   │ → email/Slack/PagerDuty
                          └─────────┘
```

## What's in here

```
.
├── app/                     Node.js + Express todo API
│   ├── src/                 Routes, DB pool, server
│   ├── tests/               Jest tests with mocked DB
│   └── Dockerfile           Multi-stage, non-root, dumb-init
├── terraform/
│   ├── modules/
│   │   ├── vpc/             3-tier subnet layout, NAT gateway
│   │   ├── alb/             ALB + target group + listeners
│   │   ├── ecs/             Cluster, service, task def, ECR, IAM, autoscaling
│   │   ├── rds/             Postgres, secrets manager integration
│   │   ├── s3/              Private bucket for static assets
│   │   └── monitoring/      CloudWatch alarms + SNS topic
│   └── environments/dev/    Wires modules together
├── .github/workflows/
│   ├── ci.yml               Tests + Terraform validate on every PR
│   └── deploy.yml           Build → ECR → ECS on push to main
├── docs/
│   └── RUNBOOK.md           Deploy, rollback, alarm response
└── README.md
```

## Prerequisites

- AWS account + CLI configured (`aws sts get-caller-identity` should work)
- Terraform ≥ 1.6
- Docker
- Node.js 20+ (for local dev)
- A registered GitHub repo (for the deploy workflow)

## First-time setup

### 1. Create the Terraform state backend

The `backend.tf` references an S3 bucket and DynamoDB table. Create them once
(by hand or with a tiny separate TF config):

```bash
# pick globally-unique names
BUCKET=my-todoapp-tfstate-12345
TABLE=todoapp-tfstate-locks
REGION=us-east-1

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
```

Then update `terraform/environments/dev/backend.tf` with the names you chose.

### 2. Apply infrastructure

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set alert_emails at minimum

terraform init
terraform plan
terraform apply
```

Expect ~15 minutes for the first apply (RDS provisioning takes most of that).

### 3. Push the first image

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo us-east-1)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

cd ../../../app
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"

aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --force-new-deployment \
  --region "$AWS_REGION"
```

### 4. Test it

```bash
ALB=$(terraform -chdir=../terraform/environments/dev output -raw alb_dns_name)
curl "http://$ALB/healthz"
curl "http://$ALB/readyz"

curl -X POST "http://$ALB/api/todos" \
  -H 'content-type: application/json' \
  -d '{"title":"first todo"}'

curl "http://$ALB/api/todos"
```

### 5. Set up GitHub Actions deploys

The deploy workflow uses OIDC to assume an AWS role — no long-lived access keys.

Create the OIDC provider and role (one-time, in the AWS account):

```bash
# OIDC provider for GitHub
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Then create an IAM role with a trust policy scoped to your repo:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<YOUR_GH_ORG>/<YOUR_REPO>:*"
      }
    }
  }]
}
```

Attach a policy granting ECR push, ECS update-service, IAM PassRole on the task roles,
and basic describe permissions.

In the GitHub repo, add these secrets:

- `AWS_DEPLOY_ROLE_ARN` — the role ARN from above
- `ALB_DNS_NAME` — output of `terraform output alb_dns_name`

Push to `main` → the `Deploy` workflow runs.

## Local development

```bash
cd app
docker run --name todo-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
npm install
DB_HOST=localhost DB_USER=postgres DB_PASSWORD=postgres DB_NAME=postgres npm run dev
```

## Costs (rough, dev defaults)

- NAT Gateway: ~$32/mo (single, shared) — biggest cost
- RDS db.t4g.micro: ~$15/mo + storage
- ECS Fargate (2 × 0.25 vCPU, 0.5GB): ~$15/mo
- ALB: ~$16/mo + LCU
- CloudWatch logs/metrics: a few dollars
- **Total: ~$80–100/mo** for dev with this config

To cut costs: stop the cluster (`desired_count = 0`) and disable the NAT gateway when not in use.

## Operations

See [`docs/RUNBOOK.md`](docs/RUNBOOK.md) for deploy, rollback, and alarm response procedures.

## What this skips (on purpose, for scope)

- CloudFront in front of S3
- WAF on the ALB
- A separate prod environment (the `environments/dev` pattern is built to copy into `environments/prod`)
- RDS Proxy (worth adding for real workloads)
- ACM cert + Route 53 (variables are wired up, just plug in your ARN and zone)
