# Todo App — Operations Runbook

This runbook covers deploy, rollback, and response to common alarms.
Anyone on-call should be able to follow these steps without prior context.

---

## Quick reference

| Need | Command / link |
|---|---|
| App URL | `terraform output alb_dns_name` |
| Logs | CloudWatch log group `/ecs/todoapp-dev` |
| ECS service | Cluster `todoapp-dev-cluster` → service `todoapp-dev` |
| Database secret | Secrets Manager → `todoapp-dev-db-credentials` |
| Alarms | CloudWatch → Alarms (filter: `todoapp-dev-`) |
| SNS alert topic | `todoapp-dev-alerts` |

---

## 1. Deploy

### Normal deploy (automated)

Merging to `main` triggers `.github/workflows/deploy.yml`, which:

1. Runs tests
2. Builds the Docker image, pushes to ECR with tag `<commit-sha>`
3. Renders a new ECS task definition pointing at the new image
4. Updates the ECS service and waits for steady state (max 10 min)
5. Hits `/healthz` through the ALB to confirm the deploy is serving traffic

If any step fails the workflow stops; the previous task definition keeps serving traffic.

### Manual deploy

```bash
# 1. Get ECR login
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# 2. Build and push
cd app
docker build -t todoapp-dev:manual .
docker tag todoapp-dev:manual <account>.dkr.ecr.us-east-1.amazonaws.com/todoapp-dev:manual
docker push <account>.dkr.ecr.us-east-1.amazonaws.com/todoapp-dev:manual

# 3. Force a new deployment using the latest task definition
aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --force-new-deployment
```

### Initial bootstrap

The very first apply has a chicken-and-egg problem: the ECS task definition references an image
that doesn't exist yet. Two options:

**Option A — bootstrap with a placeholder image first:**

```bash
# Run TF with image_tag pointing at a public hello-world placeholder
# (the TF default already creates the ECR repo first; on first apply, services may
# fail to start until you push a real image — that's expected.)

cd terraform/environments/dev
terraform init
terraform apply -var='image_tag=latest'

# Then push the real image and redeploy
cd ../../../app
ECR_URL=$(terraform -chdir=../terraform/environments/dev output -raw ecr_repository_url)
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"

aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --force-new-deployment
```

**Option B — push the image first via a separate ECR-only TF run, then apply the rest.**

---

## 2. Rollback

### Rollback an application deploy

ECS keeps previous task definitions. Roll back by pointing the service at the previous one.

```bash
# List recent task definitions (newest first)
aws ecs list-task-definitions \
  --family-prefix todoapp-dev \
  --sort DESC \
  --max-items 5

# Pick the second one in the list (the previous good version) and update the service
aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --task-definition todoapp-dev:<REVISION> \
  --force-new-deployment

# Watch the deployment
aws ecs describe-services \
  --cluster todoapp-dev-cluster \
  --services todoapp-dev \
  --query 'services[0].deployments'
```

The deploy circuit breaker (configured in the ECS module) will also auto-rollback if a new
deployment fails to reach steady state, so often you don't need to do anything.

### Rollback infrastructure changes

If a `terraform apply` caused the issue:

```bash
# In CI/CD: revert the offending PR and re-apply
git revert <bad-commit>
git push origin main

# Locally as a break-glass:
cd terraform/environments/dev
terraform plan   # confirm the diff is the inverse of what broke
terraform apply
```

If state itself is corrupt or you've lost track, you can pin to a known-good state version
in S3 (state bucket has versioning on):

```bash
aws s3api list-object-versions \
  --bucket <tfstate-bucket> \
  --prefix todoapp/dev/terraform.tfstate
# Restore a specific version, then re-init
```

### Rollback the database

DB rollbacks are riskier — restore from snapshot only as a last resort.

```bash
# List available automated snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier todoapp-dev-postgres \
  --snapshot-type automated

# Restore to a NEW instance (never overwrite the live one in place)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier todoapp-dev-postgres-restored \
  --db-snapshot-identifier <snapshot-id>

# Once verified, update the Secrets Manager secret to point at the new instance,
# then force a new ECS deploy so tasks pick up the new endpoint.
```

---

## 3. Alarm response

All alarms publish to the `todoapp-dev-alerts` SNS topic. Subscribe email/Slack/PagerDuty as needed.

### `todoapp-dev-ecs-cpu-high` — ECS CPU > 80%

**What it means:** Tasks are CPU-bound for at least 10 min.

**Investigate:**

1. CloudWatch → Container Insights → see which tasks are hot
2. Check if traffic is up: ALB `RequestCount` graph
3. Check app logs for slow loops or hot paths

**Fix:**

- If sustained legitimate load: bump `max_capacity` in the ECS module, or raise `task_cpu`
- Auto-scaling on CPU should already react (target 60%) — if it's not, check the
  `aws_appautoscaling_target` resource still exists
- If a runaway loop: roll back to last good deploy (see §2)

### `todoapp-dev-ecs-memory-high` — ECS memory > 80%

**What it means:** Tasks may OOM soon.

**Investigate:**

1. Logs for `JavaScript heap out of memory` or repeated task restarts
2. ECS task event log (Service → Events) for `OutOfMemoryError`

**Fix:**

- Short-term: increase `task_memory` (256→512→1024) in the ECS module and apply
- Find and patch the leak

### `todoapp-dev-alb-5xx-rate` — Error rate > 5%

**What it means:** > 5% of responses are 5xx over a 5-minute window.

**Investigate:**

1. CloudWatch Logs Insights — query the app log group:
   ```
   fields @timestamp, message, path, method
   | filter level = "error"
   | sort @timestamp desc
   | limit 50
   ```
2. ALB access logs (if enabled) for which targets are erroring
3. Check `/readyz` directly — is the DB reachable?

**Fix:**

- DB connectivity issue → see RDS alarms below
- App bug → roll back (see §2)
- Bad recent deploy → ECS deploy circuit breaker should already roll it back

### `todoapp-dev-alb-unhealthy-hosts` — Healthy hosts < 1

**What it means:** No tasks are passing the ALB health check.

**Investigate:**

1. ECS Service → Events — look for "task failed health checks"
2. Pull the most recent task logs in CloudWatch
3. Check `/healthz` from inside the VPC (`aws ecs execute-command`)

**Fix:**

- If startup is slow: increase `health_check_grace_period_seconds` in the ECS module
- If app crashes on boot: roll back (§2)

### `todoapp-dev-alb-target-latency-high` — p95 latency > 1s

**What it means:** Slow responses for at least 10 min.

**Investigate:**

1. RDS Performance Insights — slow queries?
2. App logs for slow handlers
3. CloudWatch metrics: ECS CPU, RDS CPU, RDS connections

**Fix:**

- Add an index, optimize a hot query, increase task count

### `todoapp-dev-rds-cpu-high` — RDS CPU > 80%

**Investigate:**

1. RDS → Performance Insights → top queries
2. App logs for unbounded queries or N+1 patterns

**Fix:**

- Add indexes
- Vertically scale: increase `instance_class` in the rds module (`db.t4g.micro` → `db.t4g.small`)
- Long-term: read replicas for read-heavy workloads

### `todoapp-dev-rds-storage-low` — Free storage < 5 GiB

**What it means:** DB will hit storage limit soon.

**Fix:**

- Storage auto-scales up to `max_allocated_storage` (50 GB by default) — bump that and apply
- Vacuum / clean up old data if appropriate

### `todoapp-dev-rds-connections-high` — Connections > 80

**What it means:** App is opening too many connections — risk of `too many clients` errors.

**Investigate:**

1. Check pool config in `app/src/db.js` (`max: 10` per task × N tasks)
2. Are tasks leaking connections? (check connection count vs running task count × pool max)

**Fix:**

- Reduce pool `max` per task
- Add a real connection pooler (PgBouncer) in front of RDS

### `todoapp-dev-app-errors-high` — > 10 error log lines in 5 min

**What it means:** Error volume spike.

**Investigate:**

CloudWatch Logs Insights:

```
fields @timestamp, message, stack
| filter level = "error"
| stats count() by message
| sort count desc
```

**Fix:** Address the most common error first — usually points right at the bug.

---

## 4. Common operations

### Connect to the running container (debugging)

```bash
# Enable execute-command if not already (one-time)
aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --enable-execute-command \
  --force-new-deployment

# Find a task ID
aws ecs list-tasks --cluster todoapp-dev-cluster --service-name todoapp-dev

# Open a shell
aws ecs execute-command \
  --cluster todoapp-dev-cluster \
  --task <task-id> \
  --container todoapp-dev \
  --interactive \
  --command "/bin/sh"
```

### Connect to the database

The DB is in a private subnet — no public access. Either:

- **Port-forward via SSM:** Use AWS Systems Manager Session Manager port forwarding
  through a small bastion in the public subnets, OR
- **Set up RDS Proxy + IAM auth** for production-grade access

```bash
# Get the password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id todoapp-dev-db-credentials \
  --query SecretString --output text | jq .
```

### Tail app logs

```bash
aws logs tail /ecs/todoapp-dev --follow --since 10m
```

### Force-restart all tasks

```bash
aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --force-new-deployment
```

### Scale up/down manually

```bash
aws ecs update-service \
  --cluster todoapp-dev-cluster \
  --service todoapp-dev \
  --desired-count 4
```

(Auto-scaling will keep it within `min_capacity`/`max_capacity` afterwards.)

---

## 5. Escalation

If you can't resolve an alarm in 30 minutes:

1. Page the next person on the rota
2. Post in `#incidents` with: alarm name, time started, what you've tried, current impact
3. Open an incident doc and start a timeline
