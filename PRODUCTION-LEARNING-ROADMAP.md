# Production Kubernetes Learning Roadmap

This file contains topics that have been selected but have not yet been fully covered. Move a topic into `PRODUCTION-LEARNING-NOTES.md` only after we have explained it and completed or intentionally skipped its learning exercise.

```text
Covered concept
      │
      ▼
Teach production abstraction
      │
      ▼
Do the smallest useful exercise
      │
      ▼
Move durable explanation to PRODUCTION-LEARNING-NOTES.md
```

MiniStack or another local simulator is not the target. If it cannot reproduce an AWS capability, record the production design and continue conceptually.

## Active order

```text
1. AWS Security Groups
2. AWS Secrets Manager and workload secret delivery
3. Helm production hardening
4. GitHub Actions CI and image delivery
5. Argo CD and GitOps releases
6. Observability
7. Reliability and production operations
```

```text
Completed: VPC and subnets
Current:   1. AWS Security Groups
Next:      2. AWS Secrets Manager and workload secret delivery
```

## 1. AWS Security Groups

```text
[ ] Security Group as a stateful virtual firewall
[ ] Inbound and outbound rules
[ ] EKS load balancer access
[ ] EKS-to-RDS access
[ ] Security-group references instead of fixed IP addresses
[ ] Public versus private subnet boundaries
[ ] Security Groups versus Network ACLs
[ ] Security Groups versus Kubernetes NetworkPolicies
[ ] Terraform representation of the rules
```

Target model:

```text
EKS application Security Group
          │ source reference
          ▼
RDS Security Group: allow TCP 5432
```

## 2. AWS Secrets Manager and workload secret delivery

This module is implemented using Synchat as the application example. The API
will receive only the credentials it needs; the Web and Crawler workloads will
not automatically share the API's secret access.

```text
[ ] Secrets Manager as the source of truth
[ ] IAM permission to read one secret
[ ] Workload identity for a Pod
[ ] External Secrets Operator
[ ] Secrets Store CSI Driver
[ ] Runtime SDK access
[ ] Secret rotation
[ ] Pod restart behavior after rotation
[ ] Avoiding credentials in Git, images, ConfigMaps, and Terraform state
```

Target model:

```text
Terraform platform layer
  ├── AWS Secrets Manager secret
  ├── IAM policy and role
  └── EKS Pod Identity association
              │
              ▼
Synchat Helm chart
  ├── API ServiceAccount
  ├── SecretProviderClass / secret reference
  └── API Deployment volume or secret reference
              │
              ▼
        Synchat API Pod
```

Secret handling is not ignored when AWS Secrets Manager is used. The source of truth moves to AWS; Kubernetes receives a controlled delivery of the value.

## 3. Helm production hardening

```text
[x] Environment-specific values files
[x] Immutable image tags instead of latest
[x] Resource requests and limits
[ ] Liveness probes
[ ] Readiness probes
[ ] Startup probes
[ ] HorizontalPodAutoscaler
[ ] PodDisruptionBudget
[x] Rolling-update behavior
[ ] Helm rollback
[ ] Helm tests
[ ] Chart dependency management (deferred)
[ ] Package and publish charts (deferred)
[ ] Chart versioning (deferred)
```

Desired chart layering:

```text
Reusable chart
      │
      ├── values-dev.yaml
      ├── values-stage.yaml
      └── values-prod.yaml
              │
              ▼
       Environment release
```

## 4. GitHub Actions + Argo CD delivery pipeline

```text
Push to GitHub
      │
      ├── Test frontend
      ├── Test backend
      ├── Test crawler
      ├── Build images
      ├── Scan images
      └── Publish immutable images to ECR
```

Topics:

```text
[ ] GitHub Actions workflow structure
[ ] Parallel frontend/backend jobs
[ ] Docker image tagging with commit SHA
[ ] ECR authentication
[ ] GitHub OIDC to AWS
[ ] Image vulnerability scanning
[x] Helm lint and template checks
[ ] Terraform fmt, validate, and plan
[ ] Artifact retention
[ ] Environment approvals
```

Combined release ownership:

```text
GitHub Actions
  ├── tests application code
  ├── lints and renders Helm
  ├── runs Helm/smoke tests
  ├── builds, scans, and publishes images
  └── updates the GitOps image tag or opens a promotion request
          │
          ▼
       Git desired state
          │
          ▼
Argo CD
  ├── renders the selected Helm chart
  ├── synchronizes Kubernetes
  ├── reports health and drift
  └── self-heals where enabled
```

## Argo CD and GitOps topics inside the combined delivery module

```text
[ ] Install Argo CD
[ ] Register a Kubernetes cluster
[ ] Create an Argo CD Application
[ ] Deploy a Helm chart through Argo CD
[ ] Use Git as the desired state
[ ] Enable automatic sync for development
[ ] Use manual sync for production
[ ] Configure sync waves
[ ] Configure health checks
[ ] Detect drift
[ ] Roll back to a previous Git commit
[ ] Use ApplicationSet for environments
[ ] Use External Secrets or SOPS
```

Target flow:

```text
Developer
    │
    ▼
GitHub application repository
    │
    ▼
GitHub Actions builds and publishes image
    │
    ▼
GitOps repository changes image tag
    │
    ▼
Argo CD detects Git change
    │
    ▼
Helm renders desired resources
    │
    ▼
Kubernetes applies the release
```

## 6. Observability

```text
[ ] Application logs
[ ] Kubernetes events
[ ] Metrics
[ ] Prometheus
[ ] Grafana
[ ] Loki or CloudWatch Logs
[ ] OpenTelemetry
[ ] Distributed tracing
[ ] HTTP latency dashboards
[ ] Error-rate dashboards
[ ] Pod restart alerts
[ ] Deployment failure alerts
[ ] Database alerts
[ ] SLOs and SLIs
```

Target flow:

```text
Application
   │
   ├── Logs
   ├── Metrics
   └── Traces
          │
          ▼
      Collector
          │
          ▼
Prometheus / Loki / Tempo / CloudWatch
          │
          ▼
      Grafana + Alertmanager
```

## 7. Reliability and operations

```text
[ ] Deployment rollback
[ ] Helm rollback versus Git revert
[ ] Database migration rollback strategy
[ ] Pod disruption behavior
[ ] Autoscaling behavior
[ ] Backup and restore verification
[ ] Incident investigation
[ ] SLO-based alerting
[ ] Disaster recovery
[ ] Cost and capacity review
```

## Later topics

These topics are important but follow the active order:

```text
[ ] Managed PostgreSQL with RDS
[ ] Database schema migrations
[ ] Sidecar patterns
[ ] Blue/green deployments
[ ] Canary deployments
[ ] Service mesh trade-offs
[ ] Disaster recovery across regions
```

Managed PostgreSQL target:

```text
Terraform
    └── RDS, subnet group, security group, backups

Kubernetes application
    └── connects to RDS through private networking

Migration process
    └── evolves schema safely during application releases
```
