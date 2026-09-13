# Terraform-managed Synchat Helm releases

This Terraform root module manages the two Helm releases that define the
platform GatewayClass and the Synchat application. It does not create an EKS
cluster yet, and it does not manage the existing Envoy Gateway controller
release (`eg`). The Kubernetes cluster must already exist and Envoy Gateway
must already be installed.

```text
Terraform
  |
  +-- helm_release.platform_gateway
  |     `-- charts/platform-gateway
  |           `-- GatewayClass: app-gatewayclass
  |
  `-- helm_release.synchat
        `-- charts/synchat
              `-- web, API, crawler, Services, ConfigMaps,
                  Gateway, and HTTPRoutes
```

The Helm provider reads the selected kubeconfig context. The context is
explicit so the same module can later target an EKS context instead of
Minikube. HashiCorp documents `helm_release` as the Terraform resource for
managing a chart release and supports local chart paths.

## First run: import the existing releases

These releases already exist because they were installed with the Helm CLI.
Import them before planning so Terraform does not try to create duplicate
releases:

```bash
cd /Users/sandipan/projects/backend_engineering/terraform-practice/synchat-deployment

terraform init

terraform import helm_release.platform_gateway \
  platform-system/platform-gateway

terraform import helm_release.synchat \
  synchat-dev/synchat
```

Inspect the plan before applying it:

```bash
terraform plan
```

The plan may show changes because the releases were originally installed by
the Helm CLI and Terraform is seeing them for the first time. Review those
changes; do not apply a plan that changes the intended chart or namespace.

Apply the Terraform-managed releases:

```bash
terraform apply
```

Verify the result:

```bash
helm list --all-namespaces
kubectl get deployments,services,configmaps,pods \
  --namespace synchat-dev
kubectl get gateway,httproute \
  --namespace synchat-dev
```

`helm list` is the reliable Helm release check. Helm releases are normally
stored as Helm state, not as a Kubernetes `HelmRelease` object.

## Target another cluster

For a kubeconfig context named `eks-dev`:

```bash
terraform plan \
  -var='kube_context=eks-dev' \
  -var='app_namespace=synchat-stage'
```

In production, use a separate Terraform state for each environment. Also do
not let Terraform and Argo CD manage the same application release at the same
time. The usual production split is:

```text
Terraform -> VPC, EKS, IAM, ECR, databases, cluster add-ons
Argo CD   -> Synchat Helm release and application promotion
Helm      -> workload templates rendered by Argo CD
```
