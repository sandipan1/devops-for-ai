# Production Kubernetes Learning Notes

This document records the transferable concepts, decisions, and diagrams from the production deployment journey.

This is a learning record, not a backlog. It contains only topics already discussed or learned. Future topics live in [PRODUCTION-LEARNING-ROADMAP.md](PRODUCTION-LEARNING-ROADMAP.md) and move here after we cover them.

MiniStack, Minikube, and other local simulators are implementation aids only. Their networking behavior, AWS API coverage, and authentication behavior are not learning objectives. When a simulator cannot reproduce a production feature, explain the production model and continue conceptually.

## Learning principles

```text
Production concept
        │
        ├── Understand the responsibility
        ├── Understand the abstraction
        ├── Implement the closest safe exercise
        └── Record production differences
```

The target environment is:

```text
AWS
 ├── Terraform provisions infrastructure
 ├── EKS runs Kubernetes
 ├── Helm packages application workloads
 ├── Argo CD manages Kubernetes releases
 ├── GitHub Actions builds and verifies changes
 ├── RDS provides managed PostgreSQL
 └── CloudWatch/OpenTelemetry/Grafana provide observability
```

## Responsibility boundaries

```text
Terraform
  └── AWS infrastructure and foundational access

Helm
  └── Kubernetes application resources and configuration

Argo CD
  └── Desired-state synchronization and release management

GitHub Actions
  └── Tests, image builds, security checks, and promotion preparation

AWS managed services
  └── PostgreSQL, container registry, DNS, certificates, load balancing,
      backups, and other cloud capabilities
```

The same resource should not normally be managed by multiple independent controllers.

## Current architecture

```text
Developer
    │
    ▼
GitHub
    │
    ├── GitHub Actions
    │     ├── Test
    │     ├── Build container images
    │     ├── Scan images
    │     └── Publish images to ECR
    │
    └── GitOps configuration
              │
              ▼
          Argo CD
              │
              ▼
             EKS
              ├── Gateway / load balancer
              ├── Synchat web
              ├── Synchat API
              └── Synchat crawler
                      │
                      ▼
                 Amazon RDS PostgreSQL
```

## Concepts already covered

```text
Kubernetes
  ├── Deployments manage replicated Pods
  ├── Services provide stable internal endpoints
  ├── ConfigMaps provide non-secret configuration
  ├── Namespaces provide logical isolation
  └── Gateway API separates traffic infrastructure from routing rules

Helm
  ├── Chart templates describe Kubernetes resources
  ├── values.yaml provides defaults
  ├── environment values override defaults
  └── a Helm release represents one installed chart instance

Terraform
  ├── Providers connect Terraform to APIs
  ├── Resources create or manage objects
  ├── Data sources read existing objects
  ├── State records Terraform ownership
  ├── IAM roles contain trust and permission policies
  └── Terraform can manage Helm releases after Kubernetes exists
```

## Gateway API model

```text
GatewayClass
  └── identifies the controller implementation

Gateway
  └── defines listeners and traffic infrastructure

HTTPRoute
  └── defines host/path routing to a Service

Service
  └── selects Pods and provides a stable destination
```

The controller must be installed separately. A `controllerName` only tells Kubernetes which controller should reconcile the resource; it does not install that controller.

## Production database model

PostgreSQL should be treated as a managed AWS dependency in the target architecture:

```text
Terraform
    │
    ▼
Amazon RDS PostgreSQL
    ├── Private subnets
    ├── Security group
    ├── Backups
    ├── High availability options
    └── Monitoring
            ▲
            │
        EKS API Pods
```

Kubernetes should receive the connection information through a secret-management mechanism. The database schema migration process must be designed separately from the application rollout.

## GitHub Actions and Argo CD model

```text
Code change
    │
    ▼
GitHub Actions
    ├── run tests
    ├── build image
    ├── push immutable image tag
    └── update GitOps image reference
            │
            ▼
       GitOps repository
            │
            ▼
          Argo CD
            ├── development: automatic sync
            ├── staging: controlled promotion
            └── production: approved promotion
                    │
                    ▼
                   EKS
```

Terraform should provision the cluster and platform foundations. Argo CD should deploy application workloads. GitHub Actions should not become a second independent deployment controller for the same workloads.

## Production differences to keep explicit

```text
Local simulator                    Real AWS
────────────────────────────────────────────────────────
Simulated EKS API                  Managed EKS control plane
Local Kubernetes node              Managed node groups / Fargate
Port-forward                       AWS load balancer + DNS
Local test credentials             IAM / OIDC / Pod Identity
Local PostgreSQL container         Amazon RDS PostgreSQL
Local image availability           ECR and image pull permissions
Manual local access                IAM-authenticated cluster access
```

When a local environment cannot model the right-hand column, focus on the responsibility, interfaces, security model, and deployment workflow instead of reproducing local networking details.

## Decision log

### Deployment ownership

Terraform provisions infrastructure. Helm describes Kubernetes workloads. Argo CD manages application release synchronization. GitHub Actions validates and packages changes.

### Database ownership

The target production database is Amazon RDS PostgreSQL, not PostgreSQL running as an application Pod. Kubernetes-side database exercises are conceptual unless they teach a transferable operational pattern.

### Local simulator policy

Do not spend learning time on simulator-specific load balancer, Docker-network, or authentication workarounds. Explain the real AWS behavior, record the limitation, and move on when the simulator diverges.

## Notes workflow

When a new concept or important decision is explained, add:

```text
1. The production responsibility
2. The relevant abstraction
3. A small ASCII diagram
4. The decision or trade-off
5. The next practical learning step
```

## Kubernetes mental model

Kubernetes is a control system. We describe the desired state, and controllers continuously work to make the actual state match it.

```text
Desired state
    │
    ▼
Kubernetes API Server
    │
    ├── Deployment controller
    ├── Service controller
    ├── Gateway controller
    └── Other controllers
            │
            ▼
       Actual state
```

A Deployment does not directly run a container. It creates and manages ReplicaSets, which create Pods.

```text
Deployment
    │ creates
    ▼
ReplicaSet
    │ creates
    ▼
Pods
    │ run
    ▼
Containers
```

If a Pod is deleted, the Deployment controller notices the difference and creates a replacement.

## Namespace model

Namespaces are logical boundaries inside one Kubernetes cluster.

```text
One EKS cluster
├── development namespace
│   ├── web Deployment
│   └── api Deployment
├── staging namespace
│   ├── web Deployment
│   └── api Deployment
└── production namespace
    ├── web Deployment
    └── api Deployment
```

The same name can exist in different namespaces:

```text
development/web-service
staging/web-service
production/web-service
```

Cluster-scoped resources, such as `GatewayClass`, are not inside a namespace. Namespaced resources, such as `Gateway`, `HTTPRoute`, `Deployment`, and `Service`, are.

## Service and Pod traffic

A Service is a stable virtual endpoint. It selects Pods using labels.

```text
Request
  │
  ▼
web-service:80
  │
  │ selector: app=web
  ├───────────────┐
  ▼               ▼
web Pod 1       web Pod 2
```

The Service port and container port are different concepts:

```text
Service port 80 ──► targetPort 8080 ──► container process :8080
```

The Service distributes traffic among ready endpoint Pods. It is a Kubernetes internal load-balancing abstraction, not automatically a public cloud load balancer.

```text
ClusterIP Service
    └── internal cluster address

NodePort Service
    └── node address + high port

LoadBalancer Service
    └── asks the cloud provider for an external load balancer
```

## Gateway API traffic model

Gateway API separates infrastructure ownership from application routing.

```text
GatewayClass
    │ selects a controller implementation
    ▼
Gateway
    │ defines listeners and infrastructure
    ▼
HTTPRoute
    │ defines hostname/path rules
    ▼
Service
    │ selects Pods
    ▼
Application
```

The controller must already be installed:

```text
GatewayClass
    │ controllerName
    ▼
Installed Gateway controller
    │ reconciles
    ▼
Gateway infrastructure
```

Writing a controller name in YAML does not install that controller.

One `GatewayClass` can be referenced by many `Gateway` objects:

```text
GatewayClass: shared-application-gateway
       │
       ├── Gateway: development-gateway
       ├── Gateway: staging-gateway
       └── Gateway: production-gateway
```

## Helm model

Helm packages Kubernetes manifests and installs them as a release.

```text
Chart
├── Chart.yaml
├── values.yaml
└── templates/
       ├── deployment.yaml
       ├── service.yaml
       └── configmap.yaml
              │
              ▼
          Helm release
              │
              ▼
       Kubernetes resources
```

`helm template` renders YAML without installing it:

```text
Chart + values
       │
       ▼
Rendered Kubernetes YAML
       │
       └── inspection only
```

`helm install` creates a release. `helm upgrade` changes an existing release. `helm rollback` returns to a previous release revision.

Values override defaults without changing templates:

```text
values.yaml                 values-dev.yaml
replicas: 3       +         replicas: 4
       │                         │
       └──────────┬──────────────┘
                  ▼
             Rendered chart
```

## Terraform model

Terraform manages external APIs through providers.

```text
Terraform configuration
          │
          ▼
Provider
          │
          ├── AWS API
          ├── Kubernetes API
          └── Helm API
```

A provider is the connection and translation layer. A resource is an object Terraform manages.

```hcl
provider "helm" {}

resource "helm_release" "application" {
  # one managed Helm release
}
```

```text
provider "helm"
    └── how Terraform connects to Helm/Kubernetes

helm_release
    └── which release Terraform creates or updates
```

A data source reads an object; it does not create it.

```text
data source
    └── read existing information

resource
    └── create and manage an object
```

For example, `aws_caller_identity.current` is named using two labels:

```text
data.aws_caller_identity.current.account_id
│    │                    │       │
│    │                    │       └── attribute
│    │                    └────────── local instance name
│    └────────────────────────────── data source type
└────────────────────────────────── Terraform namespace
```

## Terraform state and drift

Terraform state is the mapping between configuration and real objects.

```text
main.tf
  └── desired object

terraform.tfstate
  └── Terraform's recorded identity and attributes

AWS / Kubernetes
  └── actual object
```

During a plan:

```text
Configuration ──┐
                ├── Terraform plan ──► changes
State ──────────┤
                │
Provider read ──┘
```

If somebody changes an object manually, the provider reads the actual value during refresh. Terraform then compares:

```text
Configuration: replicas = 3
Actual state:  replicas = 5
                       │
                       ▼
Terraform plan detects drift
```

Terraform does not automatically create a missing object merely because a similarly named object exists. Resources represent Terraform ownership; data sources represent intentional lookup of existing objects.

## IAM model for EKS

IAM answers two different questions:

```text
Who may assume this role?
        │
        ▼
Trust policy

What may the role do?
        │
        ▼
Permission policy
```

```text
EKS service
    │ assumes
    ▼
EKS cluster IAM role
    │ receives
    ▼
AmazonEKSClusterPolicy
```

The trust policy is not the permission granted to the service. It is the rule that permits the service principal to become the role.

```text
Trust policy:
  Principal: eks.amazonaws.com
  Action:    sts:AssumeRole

Permission policy:
  Action:    eks:DescribeCluster, ...
  Resource:  selected AWS resources
```

Worker nodes use a different role:

```text
EC2 worker nodes
    │ assume
    ▼
Node IAM role
    ├── AmazonEKSWorkerNodePolicy
    └── AmazonEC2ContainerRegistryPullOnly
```

The control-plane role and node role have different responsibilities.

## EKS layers

```text
AWS account
    │
    ▼
VPC
    ├── public subnets
    └── private subnets
            │
            ▼
        EKS control plane
            │
            ▼
        Managed node group
            │
            ▼
        Kubernetes Pods
```

Subnets are IP address ranges inside a VPC. They are not individual Pods.

```text
VPC: 10.0.0.0/16
├── Subnet A: 10.0.1.0/24
│   └── nodes and infrastructure interfaces
└── Subnet B: 10.0.2.0/24
    └── nodes and infrastructure interfaces
```

Pods receive cluster networking addresses and run on nodes. The exact Pod-to-subnet implementation depends on the CNI and AWS networking configuration.

## Desired production ownership

```text
Terraform
├── VPC
├── subnets
├── IAM
├── EKS
├── node groups
├── ECR
├── RDS
├── DNS
└── certificates

Argo CD + Helm
├── Deployments
├── Services
├── ConfigMaps
├── Secrets references
├── Gateways
├── HTTPRoutes
└── application configuration
```

The boundary is not absolute, but it should be intentional. Avoid having Terraform and Argo CD independently reconcile the same application resources.

## Production delivery sequence

```text
1. Terraform provisions AWS foundation
       │
       ▼
2. EKS and platform controllers become available
       │
       ▼
3. GitHub Actions tests and builds images
       │
       ▼
4. Images are pushed to ECR with immutable tags
       │
       ▼
5. GitOps repository records the desired image tag
       │
       ▼
6. Argo CD synchronizes Helm values into EKS
       │
       ▼
7. Kubernetes rolls out the new Pods
       │
       ▼
8. Observability verifies health
```

---

# Conversation-derived reference guide

This section captures the questions that caused confusion during the learning process. Each question is mapped to the underlying production concept so it can be revisited without reconstructing the original discussion.

## Question map

```text
Question or confusion
        │
        ▼
Underlying concept
        │
        ▼
Production lesson
```

```text
"Why do I see one Pod after Helm install?"
        │
        ▼
Helm values + Deployment replicas
        │
        ▼
The chart default, not Helm itself, controls replica count

"Why does kubectl get pods not show another namespace?"
        │
        ▼
Namespace scoping
        │
        ▼
kubectl reads the current namespace unless explicitly told otherwise

"Why are Terraform and Helm both involved?"
        │
        ▼
Ownership boundaries
        │
        ▼
Terraform creates infrastructure; Helm describes workloads

"Why did Terraform say no changes?"
        │
        ▼
State refresh and desired-state comparison
        │
        ▼
No diff means configuration, state, and provider-read reality agree

"Why is the IAM policy managed by AWS?"
        │
        ▼
AWS-managed policies
        │
        ▼
AWS owns the policy document; your account attaches it to a role

"Why is Gateway Programmed=False?"
        │
        ▼
Gateway conditions and infrastructure status
        │
        ▼
Separate routing correctness from load-balancer provisioning

"Why can the page load but sending a message fails?"
        │
        ▼
Browser configuration and API reachability
        │
        ▼
The frontend and API are separate network clients
```

## 1. Kubernetes desired state versus actual state

Kubernetes resources are declarations, not imperative scripts.

```yaml
spec:
  replicas: 3
```

This means:

```text
Desired state: three matching Pods
Actual state:  zero, one, two, three, or more Pods
Controller:    continuously reconciles actual toward desired
```

```text
                    reconciliation loop
             ┌─────────────────────────────┐
             │                             │
             ▼                             │
      Desired state ──────► Compare ◄──── Actual state
             │                             │
             └───────────── Apply change ──┘
```

This is why a manually deleted Pod usually returns. The Deployment controller still sees that the desired replica count has not been satisfied.

### Deployment ownership chain

```text
Deployment
  │ owns
  ▼
ReplicaSet
  │ owns
  ▼
Pod
  │ contains
  ▼
Container
```

The Deployment is the object we normally change. We do not normally edit individual Pods because Pods are replaceable outputs of the controller.

### Why a Helm release may create one Pod

Helm does not decide the number of Pods. Helm renders and submits a Deployment. The Deployment's `spec.replicas` decides the number of Pods.

```text
values.yaml
    │
    ├── web.replicas: 3
    ▼
Helm template
    │
    ▼
Deployment.spec.replicas: 3
    │
    ▼
Three Pods
```

If the chart default is `1`, one Pod is the expected result. If the release is upgraded with `web.replicas=4`, the Deployment controller gradually creates the fourth Pod.

## 2. Namespace-scoped versus cluster-scoped resources

```text
Cluster
├── Cluster-scoped resources
│   ├── Nodes
│   ├── GatewayClass
│   ├── CustomResourceDefinitions
│   └── ClusterRoles
│
└── Namespaced resources
    ├── Deployments
    ├── Pods
    ├── Services
    ├── ConfigMaps
    ├── Secrets
    ├── Gateways
    └── HTTPRoutes
```

The same names can be reused in different namespaces:

```text
development/api-service
staging/api-service
production/api-service
```

But a `GatewayClass` name is unique across the entire cluster:

```text
cluster/app-gatewayclass
```

Useful command interpretation:

```text
kubectl get pods
    └── Pods in the current namespace

kubectl get pods -n production
    └── Pods in production

kubectl get pods --all-namespaces
    └── Pods in every namespace
```

The `kube-root-ca.crt` ConfigMap often appears in a namespace automatically. It is cluster-provided trust material, not an application ConfigMap.

## 3. Service selection and EndpointSlices

A Service does not select Pods by their names. It selects them by labels.

```yaml
Service selector:
  app: synergychat-web
```

```yaml
Pod labels:
  app: synergychat-web
```

```text
Service selector: app=synergychat-web
             │
             ├── matches Pod A
             ├── matches Pod B
             └── matches Pod C
```

Kubernetes records the selected addresses in EndpointSlices:

```text
Service: web-service:80
        │
        ▼
EndpointSlice
        ├── 10.244.0.91:8080
        ├── 10.244.0.92:8080
        └── 10.244.0.93:8080
```

The request path is:

```text
Client
  │
  ▼
Service port 80
  │
  │ chooses one ready EndpointSlice address
  ▼
Pod port 8080
```

The Service is a load-balancing abstraction inside the cluster. It is not automatically an AWS Elastic Load Balancer.

## 4. ClusterIP, NodePort, and LoadBalancer

```text
ClusterIP
─────────
Client inside cluster
        │
        ▼
Service virtual IP
        │
        ▼
Pods
```

```text
NodePort
────────
Client
  │
  ▼
Node IP : high-port
  │
  ▼
Service
  │
  ▼
Pods
```

```text
LoadBalancer
────────────
Client
  │
  ▼
Cloud load balancer
  │
  ▼
NodePort / Service routing
  │
  ▼
Pods
```

In AWS, a `LoadBalancer` Service asks AWS integration to provision an external load balancer. The Kubernetes Service object alone does not contain the physical load balancer logic.

```text
Kubernetes Service
        │ request
        ▼
Cloud controller / AWS integration
        │ creates
        ▼
AWS Network Load Balancer or equivalent
```

This distinction matters when debugging:

```text
Service has endpoints       → backend selection may work
LoadBalancer has no address → external exposure is not ready
Gateway has attached routes → routing configuration may be valid
Gateway Programmed=False    → infrastructure may still be incomplete
```

## 5. Gateway API debugging model

Gateway status is a collection of conditions, not a single overall diagnosis.

```text
GatewayClass
  └── Accepted=True
        means the controller recognizes the class

Listener
  └── Programmed=True
        means the listener configuration was accepted

HTTPRoute
  └── ResolvedRefs=True / attached
        means the route can refer to its backend

Gateway
  └── Programmed=False
        may still mean the external address is missing
```

A disciplined investigation follows the dependency chain:

```text
1. GatewayClass accepted?
          │ no → controller/class problem
          ▼ yes
2. Gateway listener programmed?
          │ no → listener/configuration problem
          ▼ yes
3. HTTPRoute attached and references resolved?
          │ no → route/backend problem
          ▼ yes
4. Generated proxy workload healthy?
          │ no → controller/proxy workload problem
          ▼ yes
5. External address assigned?
          │ no → load-balancer/infrastructure problem
          ▼ yes
       Test traffic
```

This prevents changing HTTPRoutes when the actual problem is an unassigned load-balancer address.

### GatewayClass and controller selection

```text
GatewayClass.spec.controllerName
             │
             ▼
Controller identity
             │
             ▼
Installed controller watches this class
             │
             ▼
Gateway infrastructure is created
```

`controllerName` is an identifier, not an installation command. The controller installation normally includes its Deployment, permissions, and required CRDs.

### CRDs and controllers

```text
CRD
  └── teaches the API server a new resource shape

Controller
  └── watches that resource and performs work
```

```text
EnvoyProxy CRD
        │ allows
        ▼
EnvoyProxy object
        │ watched by
        ▼
Envoy Gateway controller
        │ creates/manages
        ▼
Envoy proxy Deployment + Service
```

Installing a CRD does not install the controller. Installing a controller without its CRDs may prevent it from starting or reconciling custom resources.

## 6. Helm commands and lifecycle

```text
helm template
    └── render only; no cluster mutation

helm install
    └── create a new release

helm upgrade
    └── modify an existing release

helm upgrade --install
    └── install if missing; upgrade if present

helm list --all-namespaces
    └── show release records across namespaces
```

A Helm release is namespaced. Two releases can use the same chart but have different names, namespaces, and values.

```text
Chart: synchat
       │
       ├── Release: synchat-dev / namespace development
       ├── Release: synchat-stage / namespace staging
       └── Release: synchat-prod / namespace production
```

A release revision records successive upgrades:

```text
revision 1 ──► revision 2 ──► revision 3
   │              │              │
   └── old        └── changed    └── current
```

## 7. Helm values and configuration layering

The chart should contain reusable templates and safe defaults. Environment-specific values belong outside the reusable template logic.

```text
Chart defaults
       │
       + values-dev.yaml
       + values-stage.yaml
       + values-prod.yaml
       │
       ▼
Environment-specific rendered manifests
```

Priority is conceptually:

```text
chart values.yaml
       ◄ overridden by
environment values file
       ◄ overridden by
explicit CLI / Terraform values
```

Prefer a values file for a group of related settings:

```yaml
web:
  replicas: 4
```

Use a direct `set` value for a small, intentional override. The important production question is not which syntax is shorter; it is where the desired value is reviewed, versioned, and promoted.

## 8. Helm provider versus Helm release

```text
provider "helm"
    └── connection configuration
        ├── Kubernetes API endpoint
        ├── credentials
        └── context/configuration

resource "helm_release" "synchat"
    └── desired release
        ├── release name
        ├── namespace
        ├── chart
        ├── values
        └── upgrade behavior
```

The provider answers:

```text
"How do I connect to Helm/Kubernetes?"
```

The resource answers:

```text
"Which chart release should exist, where, and with what values?"
```

## 9. Terraform resource, data source, and state

```text
resource
  └── Terraform owns lifecycle

data source
  └── Terraform reads information

state
  └── Terraform records the relationship to the object
```

Example conceptual comparison:

```text
Hardcoded value
  ami = "ami-..."
  └── copied manually; may become stale

Data source
  data "aws_ami" "linux" { ... }
  └── provider queries AWS using filters

Resource usage
  ami = data.aws_ami.linux.id
  └── result feeds another managed object
```

A data source can be empty in configuration because its arguments may be optional. The provider still performs a read using the data source type and its configured filters or identity.

```text
data "aws_caller_identity" "current" {}
          │              │
          │              └── local label chosen by the author
          └── provider-defined data source type
```

Terraform state is persistent because Terraform needs to remember ownership and identity between runs.

```text
Run 1: create object ──► record object identity in state
Run 2: refresh        ──► read object and compare
Run 3: plan           ──► calculate change or no change
```

Remote state is a team and reliability mechanism:

```text
Developer A ─┐
Developer B ─┼──► shared remote state + locking
CI pipeline ─┘
```

Without shared state, multiple actors can make decisions from different snapshots and overwrite each other's ownership record.

## 10. Terraform import and ownership

Import does not create a resource.

```text
Already-existing object
          │
          ▼
terraform import
          │
          ▼
Terraform state records its identity
```

After import, the configuration must describe the object closely enough for Terraform to manage it without unwanted changes.

```text
Existing Helm release
        │ import
        ▼
Terraform state
        │ configuration must match
        ▼
Terraform-managed Helm release
```

An import is appropriate when ownership is intentionally transferred. It is not a substitute for deciding which system should own a resource.

## 11. IAM in EKS

IAM vocabulary:

```text
Principal
  └── identity making a request

Action
  └── operation being requested

Resource
  └── object the action targets

Policy
  └── rules that allow or deny actions

Role
  └── identity that can be assumed and receive policies
```

Generic permission decision:

```text
Principal + Action + Resource
          │
          ▼
       Policy evaluation
          │
          ▼
       Allow or Deny
```

Role assumption is a separate step:

```text
Service principal
        │
        │ allowed by trust policy
        ▼
IAM role
        │
        │ receives permission policies
        ▼
AWS API actions
```

A trust policy answers “who may become the role?” A permission policy answers “what may the role do after it is assumed?”

AWS-managed policy versus customer-managed policy:

```text
AWS-managed policy
  └── AWS owns the policy document and updates it

Customer-managed policy
  └── your account owns the policy document and updates it
```

Attaching an AWS-managed policy does not mean AWS manages your role. AWS manages that reusable policy document; your account still controls which roles receive it.

## 12. EKS role boundaries

```text
EKS control plane
        │ assumes
        ▼
Cluster IAM role
        │ permissions for
        ▼
EKS control-plane operations
```

```text
Worker node / managed node group
        │ assumes
        ▼
Node IAM role
        ├── worker-node permissions
        └── container-image pull permissions
```

The cluster role and node role are not interchangeable:

```text
Cluster role ≠ Node role ≠ Application workload role
```

Application Pods should normally receive narrowly scoped workload identity, not the broad node role.

## 13. EKS access and Kubernetes authorization

There are multiple layers:

```text
AWS identity
    │ authenticated by AWS
    ▼
EKS cluster access mapping
    │ maps identity to Kubernetes identity/groups
    ▼
Kubernetes RBAC
    │ authorizes verbs on resources
    ▼
Kubernetes API operation
```

Authentication asks:

```text
Who are you?
```

Authorization asks:

```text
What are you allowed to do?
```

Being able to obtain an AWS token does not automatically mean the Kubernetes API will authorize the identity. Both the EKS access mapping and Kubernetes permissions must be correct.

## 14. Production networking layers

```text
Internet
    │
    ▼
Route 53 DNS
    │
    ▼
AWS load balancer
    │
    ▼
Gateway / ingress data plane
    │
    ▼
Kubernetes Service
    │
    ▼
Pods
```

Internal application communication takes a different path:

```text
API Pod
  │ DNS name: crawler-service
  ▼
ClusterIP Service
  │
  ▼
Crawler Pods
```

`/etc/hosts` only changes name resolution on one machine:

```text
hostname ──► local IP lookup
```

It does not create a listener, load balancer, tunnel, port mapping, or Kubernetes route.

## 15. Application debugging model

When a page loads but an action fails, separate the components:

```text
Browser
  ├── downloads frontend assets from web route
  └── sends API request to API route
```

```text
Page loads
    └── proves web route is at least partly working

Message fails
    ├── API hostname/port may be wrong
    ├── API route may be wrong
    ├── API Pod may be unhealthy
    ├── API may reject the request
    ├── CORS may reject the browser response
    └── crawler/database dependency may fail
```

Debug in layers:

```text
1. Browser request URL
2. DNS resolution
3. Gateway listener
4. HTTPRoute hostname/path
5. Service endpoints
6. API Pod logs
7. API dependency logs
8. Application response
```

Do not conclude “the Gateway works” merely because the web page renders. The API call is a separate request with its own hostname, route, port, and backend.

## 16. Configuration versus secret data

```text
ConfigMap
  └── non-sensitive configuration
      ├── port
      ├── feature flag
      └── service hostname

Secret
  └── sensitive configuration
      ├── database password
      ├── API token
      └── signing key
```

The production flow should be:

```text
AWS Secrets Manager
        │
        ▼
External Secrets / workload identity
        │
        ▼
Kubernetes Secret
        │
        ▼
API Pod
```

A ConfigMap is not a secure place for credentials merely because Kubernetes stores it as an object.

## 17. PostgreSQL production boundary

```text
Terraform
  └── creates RDS infrastructure

RDS
  ├── owns database process
  ├── owns storage
  ├── provides backups
  └── provides managed availability options

Kubernetes
  └── runs application workloads that connect to RDS
```

The API connection path is:

```text
API Pod
  │ obtains endpoint and credentials
  ▼
Kubernetes Secret / injected environment
  │
  ▼
RDS private endpoint
  │ allowed by security groups and network routes
  ▼
PostgreSQL
```

Schema migration is a release concern, but database availability is an infrastructure concern:

```text
Terraform ──► RDS exists
Helm/Job ───► migration runs
Deployment ─► compatible application starts
```

For safe rollouts:

```text
Expand schema
    │
    ▼
Deploy code compatible with old and new schema
    │
    ▼
Backfill or migrate data
    │
    ▼
Contract old schema only after old code is gone
```

## 18. CI/CD versus GitOps

Continuous Integration validates and packages code:

```text
Git push
  │
  ▼
GitHub Actions
  ├── tests
  ├── lint
  ├── build image
  ├── scan image
  └── push immutable tag to ECR
```

GitOps continuously reconciles deployment intent:

```text
GitOps repository
  │ desired Helm values/image tag
  ▼
Argo CD
  │ compares Git with cluster
  ▼
EKS
```

The complete flow is:

```text
Source repository
        │
        ▼
GitHub Actions
        │ image: api:commit-sha
        ▼
ECR + GitOps change
        │
        ▼
Argo CD
        │
        ▼
Helm release in EKS
```

Terraform should not be used for every application rollout if Argo CD is the application deployment owner. Otherwise two reconcilers may fight:

```text
Terraform ──► Deployment replicas = 3
Argo CD ────► Deployment replicas = 5
                 │
                 ▼
            ownership conflict
```

## 19. Production troubleshooting checklist

```text
Symptom: Pod is not running
  ├── kubectl describe pod
  ├── kubectl logs
  ├── image pull status
  ├── probes
  ├── resource requests
  └── scheduling events

Symptom: Service has no traffic
  ├── selector matches Pod labels?
  ├── EndpointSlices contain addresses?
  ├── targetPort matches container port?
  └── Pods are Ready?

Symptom: Gateway is not programmed
  ├── GatewayClass accepted?
  ├── controller running?
  ├── listener programmed?
  ├── route attached?
  ├── backend references resolved?
  └── external address assigned?

Symptom: Terraform wants unexpected changes
  ├── configuration changed?
  ├── state refreshed?
  ├── resource imported correctly?
  ├── another controller owns the object?
  ├── provider version changed?
  └── mutable values such as image tags used?

Symptom: Page loads but action fails
  ├── inspect browser request URL
  ├── verify API hostname and port
  ├── verify API HTTPRoute
  ├── verify API Service endpoints
  ├── inspect API logs
  ├── inspect CORS/authentication
  └── inspect database/crawler dependency
```

## 20. Security Groups in Terraform

Terraform models the Security Groups as AWS infrastructure resources. The rule is a separate relationship between the database Security Group and the application Security Group.

```text
aws_vpc.eks.id
      │
      ├── aws_security_group.synchat_app
      │       │
      │       └── source of database access
      │
      └── aws_security_group.postgres
              │
              └── ingress rule: TCP 5432 from synchat_app
```

Production-shaped Terraform:

```hcl
resource "aws_security_group" "synchat_app" {
  name        = "synchat-app"
  description = "Network access for Synchat application workloads"
  vpc_id      = aws_vpc.eks.id

  tags = {
    Name    = "synchat-app"
    Project = "synchat"
  }
}

resource "aws_security_group" "postgres" {
  name        = "synchat-postgres"
  description = "Network access for PostgreSQL"
  vpc_id      = aws_vpc.eks.id

  tags = {
    Name    = "synchat-postgres"
    Project = "synchat"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = aws_security_group.synchat_app.id

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
  description = "Allow Synchat application workloads to reach PostgreSQL"
}
```

The Terraform dependency is visible in the references:

```text
aws_security_group.postgres.id
              │
              ▼
database ingress rule
              ▲
              │
aws_security_group.synchat_app.id
```

This configuration creates firewall objects and a rule. It does not create EKS, RDS, Pods, or the database connection itself.

The resource name `aws_security_group.postgres` is only a label for the database firewall. It does not create PostgreSQL or Amazon RDS.

```text
aws_security_group.postgres
        └── firewall around a future database

aws_db_instance.postgres
        └── the RDS database itself
```

At this stage, only the first object exists in the configuration. RDS will be a separate Terraform lesson.

### Reading an ingress rule line by line

```hcl
resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
```

This declares one Terraform-managed inbound rule. The final label, `postgres_from_app`, is only Terraform's local name for this rule.

```hcl
security_group_id = aws_security_group.postgres.id
```

This identifies the Security Group receiving the traffic. The rule is added to the PostgreSQL Security Group.

```hcl
referenced_security_group_id = aws_security_group.synchat_app.id
```

This identifies the allowed source. Traffic from resources using the application Security Group may match this rule.

```text
Source:  synchat_app Security Group
             │
             │ allowed by this rule
             ▼
Target:  postgres Security Group
             │
             ▼
        PostgreSQL service
```

```hcl
ip_protocol = "tcp"
```

Only TCP traffic is allowed. PostgreSQL uses TCP for its normal client connection.

```hcl
from_port = 5432
to_port   = 5432
```

The allowed port range contains only port `5432`. Because both values are equal, this is one port rather than a range.

```text
Allowed:
  TCP 5432 ──► PostgreSQL

Not allowed by this rule:
  TCP 80
  TCP 443
  TCP 5433
  UDP 5432
```

```hcl
description = "Allow Synchat application workloads to reach PostgreSQL"
```

This is human-readable documentation stored with the AWS rule. It does not affect traffic.

The complete rule means:

```text
Allow TCP connections
from the Synchat application Security Group
to the PostgreSQL Security Group
on port 5432.
```

It does not create PostgreSQL, credentials, a database endpoint, or a Kubernetes Service.

### Completing the application traffic path

The database rule is only one part of the production path. The complete abstract model has two application tiers:

```text
Internet
   │
   │ HTTPS :443
   ▼
Load Balancer
   │
   │ application port
   ▼
Application
   │
   │ PostgreSQL :5432
   ▼
RDS PostgreSQL
```

This normally requires two inbound relationships:

```text
1. Load Balancer SG ──► Application SG
                         application port

2. Application SG ─────► Database SG
                         PostgreSQL port 5432
```

```text
Load Balancer SG
        │ TCP application port
        ▼
Application SG
        │ TCP 5432
        ▼
Database SG
```

An inbound rule belongs to the destination Security Group:

```text
Application SG rule
  └── allows the Load Balancer SG to enter the application tier

Database SG rule
  └── allows the Application SG to enter the database tier
```

Security Groups also have outbound rules. The default Security Group configuration commonly permits outbound traffic, but a restricted production design can explicitly allow only required destinations:

```text
Application SG outbound
  └── allow TCP 5432 to Database SG
```

The key direction rule is:

```text
The rule is written on the side being entered.

Traffic enters the Application  → rule belongs to Application SG
Traffic enters the Database      → rule belongs to Database SG
```

The exact application port and the exact AWS network interface used by EKS depend on the load-balancing and Pod-networking design. The tier relationship remains the same.

### EKS load-balancer target modes

In real EKS, the AWS Load Balancer Controller can register either worker nodes or Pod IP addresses as load-balancer targets. This choice changes which Security Group receives the load-balancer traffic.

#### Instance target mode

```text
AWS Load Balancer
        │
        │ listener traffic
        ▼
Worker Node : NodePort
        │
        ▼
Kubernetes Service
        │
        ▼
Application Pod
```

The node Security Group must allow the Load Balancer Security Group to reach the NodePort.

```text
Load Balancer SG
        │
        │ allowed NodePort
        ▼
Node SG
        │
        ▼
Service → Pod
```

#### IP target mode

```text
AWS Load Balancer
        │
        │ application traffic
        ▼
Pod IP address
        │
        ▼
Application container
```

The Security Group associated with the Pod's network interface must allow the Load Balancer Security Group to reach the application port.

```text
Load Balancer SG
        │
        │ allowed application port
        ▼
Application Pod SG
        │
        ▼
Application container
```

IP target mode removes the extra NodePort and Service hop. AWS EKS guidance recommends considering IP targets because traffic and health checks reach the Pods directly. The AWS Load Balancer Controller supports both target modes. See the [Amazon EKS load-balancing guidance](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html).

### Why the source Security Group can be confusing

The source of traffic depends on where the Pod's network identity lives:

```text
Instance targets
  └── Load Balancer SG → Node SG

IP targets with Pod Security Groups
  └── Load Balancer SG → Application Pod SG

IP targets without dedicated Pod Security Groups
  └── verify which node or Pod network interface receives the traffic
```

EKS also supports assigning Security Groups directly to Pods through the Amazon VPC CNI. That is a separate feature from ordinary Kubernetes labels and Services. See the [EKS Security Groups for Pods documentation](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html).

The database relationship is independent of the north-south load-balancer mode:

```text
Load Balancer SG ──► Application SG or Node SG
Application SG ────► Database SG :5432
```

First choose the load-balancer target mode; then write the matching Terraform rules. This prevents opening the database or nodes to an incorrect source.

### NodePort in one example

### Simple picture: node, Service, and Pod

```text
Cluster
  └── Worker node
        ├── Pod
        │     └── application container
        └── Pod
              └── application container
```

```text
Worker node = a machine that runs Pods
Pod         = a small wrapper around one or more containers
Service     = a stable network address that sends traffic to Pods
```

A worker node is usually an EC2 instance in a real EKS cluster:

```text
AWS EC2 instance
        │
        └── Kubernetes worker node
                │
                └── runs Pods
```

The worker node has a private IP address:

```text
Worker node private IP: 10.0.1.25
```

The Pod has its own cluster network address:

```text
Pod IP: 10.244.2.17
```

The Pod IP is not normally used by clients because Pods are replaceable:

```text
Pod A: 10.244.2.17  ── deleted
Pod B: 10.244.3.41  ── created as replacement
```

The Service gives clients a stable address:

```text
web-service:80
        │
        ├── Pod A
        ├── Pod B
        └── Pod C
```

In the NodePort path, the request travels like this:

```text
Client
  │
  ▼
Worker node IP :30080
  │
  │ NodePort
  ▼
Service :80
  │
  │ chooses one ready Pod
  ▼
Pod :8080
```

The labels mean different things:

```text
Worker node IP :30080
  └── machine address + NodePort entry point

Service :80
  └── stable Kubernetes Service port

Pod :8080
  └── application container's listening port
```

The Service is needed because Pod IPs can change while the Service name and virtual IP remain stable.

### Reading the Synchat API Service template

```yaml
apiVersion: v1
kind: Service
```

This says: create a Kubernetes Service using the core `v1` API.

```yaml
metadata:
  name: {{ .Values.api.serviceName }}
```

Helm replaces the template expression with a value from `values.yaml`. If the value is `api-service`, Kubernetes creates:

```text
Service name: api-service
```

```yaml
labels:
  app: {{ .Values.api.name }}
  {{- include "synchat.labels" . | nindent 4 }}
```

These are labels on the Service object. They help identify and organize the object. They do not decide which Pods receive traffic.

```yaml
spec:
  type: ClusterIP
```

`ClusterIP` means the Service is reachable inside the Kubernetes cluster. It does not expose the API directly to the internet and does not open a NodePort.

```text
Other Pods ──► api-service:80 ──► API Pods

Internet ──✗──► api-service directly
```

```yaml
selector:
  app: {{ .Values.api.name }}
```

This is how the Service finds the API Pods. The selector must match the labels on the API Pod template.

```text
Service selector:
  app: synergychat-api

API Pod labels:
  app: synergychat-api
       │
       └── match → Pod becomes a Service endpoint
```

```yaml
ports:
  - name: http
    protocol: TCP
    port: {{ .Values.api.servicePort }}
    targetPort: http
```

The ports describe two different sides of the connection:

```text
Service port 80 ──► named Pod port "http" ──► container port 8080
```

`name: http` gives the Service port a name. `targetPort: http` means “send traffic to the container port named `http` in the selected Pod.” It does not mean the numeric port is `80`.

The complete request path is:

```text
API Pod or Gateway
        │
        ▼
api-service:80
        │
        │ selector chooses ready Pods
        ▼
API Pod :8080
```

If the selector matches no Pods, the Service still exists but has no usable endpoints. If the Pod does not define a container port named `http`, the named `targetPort` cannot resolve correctly.

A NodePort is a Kubernetes Service exposure mode. It opens a high-numbered port on every worker node.

```text
Service configuration:
  service port: 80
  target port:  8080
  NodePort:     30080
```

The instance-target path is:

```text
Load Balancer
      │
      ▼
Node IP :30080
      │
      ▼
Service port 80
      │
      ▼
Pod IP :8080
```

`30080` is not the application container port. It is the node-level entry point that forwards traffic to the Service and then to the Pod.

The direct IP-target path skips the NodePort entry point:

```text
Load Balancer
      │
      ▼
Pod IP :8080
```

Use instance targets when the load balancer must target worker nodes, the networking design does not support direct Pod targets, or a legacy setup depends on NodePorts. Use IP targets when the EKS networking and load-balancer controller support direct Pod routing and you want fewer hops and direct health checks.

### Where an ingress rule belongs

An ingress rule is written on the Security Group of the resource being entered.

```text
Source                         Destination
synchat application ─────────► PostgreSQL
```

The rule is attached to the destination:

```text
PostgreSQL Security Group
  inbound rule:
    source = Synchat application Security Group
    port   = 5432
```

Terraform represents that relationship as a separate rule resource:

```hcl
resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = aws_security_group.synchat_app.id

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}
```

```text
resource type
  └── aws_vpc_security_group_ingress_rule

Terraform local name
  └── postgres_from_app

security_group_id
  └── target / destination SG: postgres

referenced_security_group_id
  └── source SG: synchat_app
```

So the rule is not floating independently:

```text
Terraform rule object
        │ attaches to
        ▼
PostgreSQL Security Group
        │ allows source
        ▼
Synchat application Security Group
```

In the AWS console, this rule appears in the inbound rules of the PostgreSQL Security Group. For an outbound rule, the same idea applies to the Security Group whose traffic is leaving.

```text
Terraform Security Groups
        │
        └── allow network path
                │
                ▼
Application configuration and credentials
        │
        └── still required to connect to PostgreSQL
```

In real EKS, the source Security Group must be attached to the traffic source. Depending on the EKS networking design, traffic may originate through node network interfaces or through dedicated security groups for Pods. The rule's design must match that networking choice.

### Implementing Load Balancer access

Create a separate Security Group for the AWS Load Balancer:

```hcl
resource "aws_security_group" "load_balancer" {
  name        = "synchat-load-balancer"
  description = "Security group for the public application load balancer"
  vpc_id      = aws_vpc.eks.id
}
```

The next rule depends on the selected target mode.

#### Option A: Load Balancer to worker nodes

```text
AWS Load Balancer
        │
        │ TCP NodePort 30080
        ▼
Worker node
        │
        ▼
Kubernetes Service
        │
        ▼
Application Pod
```

Terraform rule:

```hcl
resource "aws_vpc_security_group_ingress_rule" "node_from_load_balancer" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.load_balancer.id

  ip_protocol = "tcp"
  from_port   = 30080
  to_port     = 30080
  description = "Allow the load balancer to reach the application NodePort"
}
```

Read the rule as:

```text
Attach this rule to the Node SG.
Allow the Load Balancer SG to enter it.
Only on NodePort 30080.
```

The important detail is that instance targets require a NodePort. AWS EKS guidance describes this extra path as Load Balancer → worker node and NodePort → Service → Pod. [Amazon EKS load-balancing guidance](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html)

#### Option B: Load Balancer directly to Pod IPs

```text
AWS Load Balancer
        │
        │ TCP application port 8080
        ▼
Application Pod network interface
        │
        ▼
Application container
```

Terraform rule when the Pods have a dedicated Security Group:

```hcl
resource "aws_security_group" "synchat_pods" {
  name        = "synchat-pods"
  description = "Security group for Synchat Pods"
  vpc_id      = aws_vpc.eks.id
}

resource "aws_vpc_security_group_ingress_rule" "pods_from_load_balancer" {
  security_group_id            = aws_security_group.synchat_pods.id
  referenced_security_group_id = aws_security_group.load_balancer.id

  ip_protocol = "tcp"
  from_port   = 8080
  to_port     = 8080
  description = "Allow the load balancer to reach application Pod targets"
}
```

Read the rule as:

```text
Attach this rule to the Pod SG.
Allow the Load Balancer SG to enter it.
Only on the application port 8080.
```

IP targets avoid the NodePort hop and send traffic directly to Pod IPs. They require a compatible EKS networking and load-balancer-controller setup. AWS documents this as the direct Pod-target path. [Assign Security Groups to Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)

#### Do not combine the rules accidentally

```text
Instance target design
  └── Load Balancer SG → Node SG : NodePort

IP target design
  └── Load Balancer SG → Pod SG : application port
```

The database rule is a separate east-west relationship:

```text
Application SG or Node SG
            │ TCP 5432
            ▼
Database SG
```

The final source Security Group for the database depends on where the application traffic originates in the selected EKS networking mode.

### Attaching a Pod Security Group

Creating an AWS Security Group does not automatically attach it to a Kubernetes Pod.

```text
Terraform
  └── creates synchat_app Security Group

Kubernetes SecurityGroupPolicy
  └── selects the API Pods

Amazon VPC CNI / VPC resource controller
  └── attaches the Pod networking to the selected SG
```

Conceptual Kubernetes resource:

```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: synchat-api-network-policy
  namespace: synchat-dev
spec:
  podSelector:
    matchLabels:
      app: synergychat-api
  securityGroups:
    groupIds:
      - <Terraform-created-application-SG-id>
```

The selector connects the policy to the Pods:

```text
SecurityGroupPolicy selector
  app: synergychat-api
          │
          ▼
API Pods with the same label
          │
          ▼
Application Security Group is attached to their Pod networking
```

This feature has EKS prerequisites. The Amazon VPC CNI must support security groups for Pods, the cluster must be configured for Pod ENIs, the cluster role needs the VPC resource-controller permission, and the worker instance types must support the required ENI feature. AWS creates trunk and branch network interfaces for this model. See [Configure security groups for Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-pods-deployment.html).

SecurityGroupPolicy applies to newly scheduled Pods. Changing the policy does not automatically change the network identity of already-running Pods; a controlled rollout is needed.

This is why Pod Security Groups are powerful but more involved than using the node Security Group:

```text
Node Security Group
  └── simpler; many Pods may share it

Pod Security Group
  └── finer isolation; requires VPC CNI and ENI support
```

### What Amazon VPC CNI does here

The Amazon VPC CNI is the Kubernetes networking plugin that runs on EKS worker nodes. It is responsible for giving Pods network addresses and connecting Pod traffic to the AWS VPC.

```text
Kubernetes Pod
      │ asks for network
      ▼
Amazon VPC CNI (`aws-node`)
      │ assigns/connects
      ▼
AWS VPC network interface and IP
```

In the normal configuration:

```text
Worker node ENI
  └── Node Security Group
        │
        └── many Pods use the node's network security boundary
```

When Pod Security Groups are enabled:

```text
Selected Pod
      │
      ▼
Pod Security Group policy
      │
      ▼
VPC resource controller
      │
      ▼
Branch ENI with Pod Security Group
```

The Pod now has a separate AWS-level security boundary instead of relying only on the node's Security Group. AWS uses trunk and branch ENIs to implement this feature. See [EKS Security Groups for Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-pods-deployment.html).

### Cost and operational trade-off

```text
Node SG
  ├── no extra Pod-SG feature setup
  ├── simpler operations
  ├── high Pod density is easier
  └── coarser network isolation

Pod SG
  ├── finer workload isolation
  ├── additional VPC CNI configuration
  ├── branch-ENI and IP capacity requirements
  ├── possible Pod startup latency
  └── more operational constraints
```

The main concern is usually not a separate per-Security-Group charge. The practical costs are additional ENI/IP capacity, supported-instance requirements, possible lower scheduling density, and more operational complexity. AWS documents that Pod Security Groups can increase startup latency and depend on branch-ENI capacity. See [EKS Security Groups for Pods considerations](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html).

### Which pattern is standard?

There is no single answer for every EKS workload:

```text
Simple application
  └── node Security Group + Kubernetes NetworkPolicy

Application accessing RDS or another VPC service
  └── consider a dedicated Pod Security Group

Multiple workloads with different AWS access requirements
  └── Pod Security Groups provide finer isolation
```

AWS describes Pod Security Groups as useful when applications need controlled access to AWS services such as RDS. They are a security-isolation choice, not a mandatory replacement for node Security Groups. See [EKS Security Groups best practices](https://docs.aws.amazon.com/eks/latest/best-practices/sgpp.html).

For Synchat, the production design we are studying is:

```text
API Pods
  └── dedicated application Pod SG
        └── allowed to reach RDS :5432

Web Pods
  └── separate policy if their AWS access differs
```

This gives the API database access without automatically giving every Pod on the same node access to RDS.

### Security Group versus Kubernetes NetworkPolicy

These controls operate at different boundaries:

```text
API Pod
  │
  ├── Kubernetes NetworkPolicy
  │     controls Pod-to-Pod traffic
  │
  └── Pod Security Group
        controls Pod-to-AWS-resource traffic
```

For Synchat:

```text
Web Pod ──────────────► API Pod
          NetworkPolicy

API Pod ──────────────► Crawler Pod
          NetworkPolicy

API Pod ──────────────► RDS PostgreSQL
          Pod SG + RDS SG
```

A NetworkPolicy can express rules such as:

```text
Allow web Pods to call API Pods on TCP 8080.
Allow API Pods to call crawler Pods on TCP 8080.
Deny other Pod-to-Pod traffic by default.
```

An AWS Security Group is better suited to the RDS boundary:

```text
API Pod SG ── TCP 5432 ──► RDS SG
```

A NetworkPolicy is not a replacement for the RDS Security Group, and an RDS Security Group is not a replacement for Pod-to-Pod policy. AWS documents NetworkPolicy as the control for in-cluster traffic and Pod Security Groups as the control for AWS-service access. See [EKS network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html).

### NetworkPolicy in the Synchat Helm chart

The chart now contains an optional `networkpolicy.yaml` template. It is disabled by default until the cluster's network-policy enforcement is intentionally enabled:

```yaml
networkPolicy:
  enabled: false
  apiPort: 8080
  crawlerPort: 8080
```

When enabled, it allows:

```text
web Pods ── TCP 8080 ──► API Pods
API Pods ── TCP 8080 ──► crawler Pods
Envoy Gateway namespace ── TCP 8080 ──► API Pods
```

The policy uses the Pod port `8080`, not the Service port `80`:

```text
HTTPRoute / Service :80 ──► Pod :8080
NetworkPolicy checks ───────────────► Pod :8080
```

The API rule also allows the Envoy Gateway namespace because external requests enter through the Gateway before reaching the API Service. A policy that allowed only the web Pods would accidentally block the Gateway's API traffic.

The chart was rendered with the feature enabled to verify the YAML. It has not been enabled in the deployed release yet.

### The security design we are using for Synchat

We are using all three layers intentionally:

```text
1. Node Security Group
   └── required baseline for EKS nodes and cluster networking

2. API Pod Security Group
   └── allows API Pods to reach RDS :5432

3. Kubernetes NetworkPolicy
   └── limits web → API and API → crawler Pod traffic
```

```text
AWS network boundary
  Node SG / Pod SG / RDS SG
          │
          ▼
Kubernetes Pod boundary
  NetworkPolicy
          │
          ▼
Application boundary
  authentication and authorization
```

The Pod Security Group does not replace the Node Security Group. The Node Security Group remains part of the EKS baseline; the Pod Security Group adds finer isolation for selected workloads.

NetworkPolicy is not required for the API to reach RDS, but it is a production defense-in-depth control for the in-cluster web, API, and crawler relationships.

### Service versus NetworkPolicy

A Service and a NetworkPolicy participate in the same request, but they answer different questions.

```text
Web Pod
  │ sends request to api-service
  ▼
Service
  │ answers: which matching API Pod should receive it?
  ▼
NetworkPolicy check
  │ answers: is the Web Pod allowed to send to the API Pod?
  ▼
API Pod
```

The Service provides discovery and routing:

```text
api-service
  └── selector: app=synergychat-api
        ├── API Pod 1
        └── API Pod 2
```

The Service does not normally verify which Pod is calling it:

```text
Web Pod ─────────────► api-service ─────────────► API Pod
Crawler Pod ─────────► api-service ─────────────► API Pod
Unknown Pod ──────────► api-service ─────────────► API Pod
```

If the network path exists and no NetworkPolicy denies the traffic, the caller may reach the Service.

NetworkPolicy adds the source/destination restriction:

```text
NetworkPolicy:
  allow source: web Pods
  allow destination: API Pods
  allow port: 8080
```

```text
Web Pod       ── allowed ──► api-service ──► API Pod
Crawler Pod   ── denied  ──► api-service
Unknown Pod   ── denied  ──► api-service
```

In short:

```text
Service       = destination and load balancing
NetworkPolicy = caller authorization at the network layer
```

### Current Terraform implementation

The current exercise models the IP-target design with three Security Groups:

```text
load_balancer SG
        │ TCP 8080
        ▼
synchat_app SG
        │ TCP 5432
        ▼
postgres SG
```

The `synchat_app` Security Group is currently being used as the application/Pod-side Security Group. The `app_from_load_balancer` rule opens application port `8080`, while `postgres_from_app` opens database port `5432`.

```text
security-groups.tf
  ├── synchat_app SG
  ├── postgres SG
  ├── load_balancer SG
  ├── app_from_load_balancer rule :8080
  └── postgres_from_app rule :5432
```

Writing these resources does not yet attach `synchat_app` to Pods or configure an AWS Load Balancer target group. Those are separate EKS and AWS Load Balancer Controller configuration steps.

### Clarifying Pod networking, NodePort, and Pod Security Groups

These are three different decisions:

```text
1. Target mode
   How does the Load Balancer reach the workload?
   ├── instance target → worker node
   └── IP target       → Pod IP

2. Network identity
   Which AWS network interface and Security Group represent the workload?
   ├── node Security Group
   └── dedicated Pod Security Group

3. Kubernetes Service exposure
   Does the Service need a NodePort?
   ├── instance target → usually yes
   └── IP target       → direct Pod target; NodePort may not be needed for LB routing
```

### What NodePort means

`NodePort` is a Kubernetes Service type. It reserves one high-numbered port on every worker node.

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080
```

This creates the following path:

```text
Any worker node IP :30080
          │
          ▼
Kubernetes Service :80
          │
          ▼
Selected Pod :8080
```

The NodePort is a node-level doorway. It is not a Pod port and it is not the application port.

```text
nodePort:    30080  → doorway on every worker node
Service port: 80     → stable Kubernetes Service port
targetPort:   8080  → application container port
```

### What “Pod networking supports Pod targets” means

For IP target mode, the AWS Load Balancer must be able to send traffic to the Pod IP directly:

```text
AWS Load Balancer
        │
        │ Pod IP is registered as a target
        ▼
Pod IP :8080
```

In a production EKS design, this normally means the Pod receives an address that is routable inside the VPC through the Amazon VPC CNI. The AWS Load Balancer Controller discovers the Pod targets and configures the AWS target group. See [Amazon EKS load-balancing guidance](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html).

### IP target mode and Pod Security Groups are not the same thing

```text
IP target mode
  └── describes the Load Balancer destination: Pod IP

Pod Security Groups
  └── describes which AWS firewall rules apply to the Pod network identity
```

Possible combinations:

```text
Instance target + Node SG
  Load Balancer → Node IP : NodePort

IP target + Node SG
  Load Balancer → Pod IP
  Pod traffic uses the node's Security Group model

IP target + Pod SG
  Load Balancer → Pod IP
  Pod has a dedicated Security Group
```

Security Groups for Pods are an additional EKS networking feature, not a requirement for every IP-target setup. They are useful when different workloads need different AWS-level network policies. See [Assign Security Groups to Pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html).

### Why instance mode was shown first

Instance mode was shown first only because it makes the NodePort path visible:

```text
Load Balancer → Node → NodePort → Service → Pod
```

It was not a recommendation for your final architecture. For the real AWS design, we should prefer:

```text
IP target mode
        │
        ▼
Pod IP targets
        │
        ▼
Dedicated Pod SG when workload-level AWS firewall rules are needed
```

We will use instance mode only as a comparison, then focus implementation on the IP-target design that matches the supported EKS networking configuration.

### How a NetworkPolicy becomes enforcement in EKS

The `NetworkPolicy` object is only the desired rule. Kubernetes stores the rule in
the API server; a networking component must observe it and enforce it on packets.

```text
Helm renders NetworkPolicy YAML
              │
              ▼
Kubernetes API server stores the object
              │
              ▼
EKS network-policy implementation watches the object
              │
              ▼
The CNI / policy agent programs packet filtering
              │
              ▼
Allowed traffic passes; other traffic is blocked
```

Without an enforcing network-policy implementation, this can happen:

```text
NetworkPolicy exists ── yes
Traffic is restricted ── not necessarily
```

Amazon EKS uses the Amazon VPC CNI for Pod networking on EC2 nodes. The VPC CNI
has a network-policy feature that can enforce standard Kubernetes `NetworkPolicy`
objects. The feature must be enabled and compatible with the cluster's CNI
add-on configuration; creating YAML alone does not turn it on. AWS documents
that the feature uses a `PolicyEndpoint` CRD and a network-policy agent to apply
the policy. See [EKS network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html)
and [EKS network-policy troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/network-policies-troubleshooting.html).

The production ownership is therefore split:

```text
Terraform / EKS platform layer
  └── installs and configures the VPC CNI add-on and its IAM prerequisites

Helm / application layer
  └── creates the application's NetworkPolicy objects

EKS CNI network-policy agent
  └── enforces those objects at runtime
```

Our Synchat chart currently keeps the feature opt-in:

```yaml
networkPolicy:
  enabled: false
```

When enabled, the chart expresses the intended application flow:

```text
Envoy Gateway ───────► API Pods :8080
Web Pods ────────────► API Pods :8080
API Pods ────────────► Crawler Pods :8080
```

The policy port is `8080` because NetworkPolicy matches the destination Pod's
network port. It is not the Service's stable port `80`:

```text
caller → Service :80 → selected Pod :8080
                         ▲
                         └── NetworkPolicy evaluates this Pod-facing port
```

The current policies are ingress policies only. They restrict who may enter
the API and crawler Pods, while egress remains unrestricted. A stricter
production design may add default-deny egress and then explicitly allow DNS,
database access, AWS endpoints, and required service calls. That is a separate
hardening step because accidentally blocking DNS or telemetry can make a healthy
application appear broken.

```text
Current learning policy
  ├── restrict API ingress
  ├── restrict crawler ingress
  └── leave egress open

Later production hardening
  ├── deny ingress by default
  ├── deny egress by default
  ├── allow DNS
  ├── allow required application paths
  └── allow database / AWS endpoints deliberately
```

The next real-AWS implementation step is not to change the application chart
again. It is to verify the EKS networking add-on and enable network-policy
enforcement through the platform layer, then deploy the chart with
`networkPolicy.enabled=true` and test the intended allow/deny paths.

### Adding the EKS networking add-on with Terraform

In a real EKS cluster, the Amazon VPC CNI is managed as an EKS add-on. It is
platform infrastructure, so it belongs in the Terraform EKS/platform layer,
not in the Synchat application Helm chart.

```text
Terraform
  │
  ├── EKS cluster
  ├── VPC CNI add-on
  ├── CoreDNS add-on
  └── kube-proxy add-on
        │
        ▼
      EKS nodes and Pods
```

A production Terraform resource has this general shape:

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  # Pin a version compatible with the EKS Kubernetes version.
  addon_version = var.vpc_cni_addon_version

  # The VPC CNI reads this configuration and enables policy enforcement.
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  # In production, this should be an IAM role for the add-on's service account
  # using EKS Pod Identity or IRSA, depending on the platform standard.
  service_account_role_arn = aws_iam_role.vpc_cni.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.vpc_cni,
  ]
}
```

The exact add-on version is not arbitrary. It must be compatible with the
Kubernetes version and the EKS add-on version available in the target AWS
region. Pinning it makes upgrades deliberate and reviewable.

The add-on also needs AWS permissions. The important distinction is:

```text
EKS cluster role
  └── lets the EKS control plane manage the cluster

VPC CNI add-on role
  └── lets the networking component manage ENIs and Pod networking
```

Conceptually, the add-on IAM role has a trust policy for the add-on's service
identity and a permission policy such as `AmazonEKS_CNI_Policy`:

```text
VPC CNI service account
          │
          │ assumes
          ▼
VPC CNI IAM role
          │
          │ grants
          ▼
AmazonEKS_CNI_Policy
          │
          ▼
Create/manage the networking resources required by Pods
```

The role is normally connected through EKS Pod Identity or IAM Roles for
Service Accounts (IRSA). That connection requires platform configuration such
as an EKS OIDC provider when IRSA is used. The application Pods do not receive
this role merely because they use the VPC CNI.

There are therefore three separate Terraform concerns:

```text
1. aws_eks_cluster
   Creates the EKS control plane.

2. aws_eks_addon.vpc_cni
   Installs/configures the cluster networking add-on.

3. aws_iam_role.vpc_cni + policy attachment
   Gives that add-on the AWS permissions it needs.
```

Then the application layer is enabled separately:

```text
Terraform platform layer
  └── VPC CNI + network-policy enforcement enabled
          │
          ▼
Helm application layer
  └── networkPolicy.enabled=true
          │
          ▼
EKS enforces Synchat's API/crawler traffic rules
```

This is different from placing `NetworkPolicy` YAML in Terraform. Terraform
can install the add-on, while Helm owns the application policy objects. Each
tool manages the layer it is responsible for.

AWS recommends using the managed VPC CNI add-on and assigning its required IAM
permissions through the cluster's identity mechanism. See [Create the Amazon
VPC CNI add-on](https://docs.aws.amazon.com/eks/latest/userguide/vpc-add-on-create.html),
[Amazon EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html),
and [Configure the VPC CNI for network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html).

### AWS Secrets Manager and EKS workloads

Application credentials should not be placed in Git, Docker images, Helm
values, or Terraform state as plaintext. The production boundary is:

```text
AWS Secrets Manager
  └── stores the database password / API key

EKS Pod Identity
  └── gives one Kubernetes service account an IAM role

Secrets Store CSI Driver + AWS provider
  └── retrieves the authorized secret for the Pod

Application Pod
  └── reads the secret at runtime
```

The complete request path is:

```text
Application Pod
      │ uses its Kubernetes ServiceAccount
      ▼
EKS Pod Identity association
      │ maps ServiceAccount → IAM role
      ▼
IAM policy allows secretsmanager:GetSecretValue
      │ for a specific secret ARN
      ▼
AWS Secrets Manager
      │ returns the authorized value
      ▼
CSI driver mounts the value into the Pod
      ▼
Application reads a file such as /mnt/secrets/db-password
```

The IAM permission is scoped to the secret, not to all Secrets Manager
resources:

```text
Synchat API ServiceAccount
          │
          ▼
Synchat API IAM role
          │
          └── secretsmanager:GetSecretValue
              Resource: arn:aws:secretsmanager:...:secret:synchat/prod/api-*
```

This is least privilege: the crawler does not automatically receive the API's
database credentials, and the web Pods do not need access to the database
secret at all.

AWS supports retrieving Secrets Manager values into EKS Pods through the AWS
Secrets and Configuration Provider (ASCP) for the Secrets Store CSI Driver.
AWS documents both IRSA and EKS Pod Identity; for a new EKS design, Pod
Identity is the simpler default to learn because it maps a role directly to a
Kubernetes ServiceAccount without requiring an OIDC provider. See [AWS Secrets
Manager with EKS Pods](https://docs.aws.amazon.com/eks/latest/userguide/manage-secrets.html),
[Secrets Manager EKS integration](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrate_eks.html),
and [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).

The platform/application ownership is:

```text
Terraform platform layer
  ├── Secrets Manager secret container/policy boundary
  ├── IAM role and least-privilege permission
  ├── EKS Pod Identity association
  └── CSI/ASCP platform components

Helm application layer
  ├── ServiceAccount used by the API
  ├── SecretProviderClass referring to the secret name
  └── Deployment volume mount

Application code
  └── reads the mounted secret file
```

The application should refer to a stable secret name, while the secret value
is managed outside Git:

```text
Git / Helm values
  └── secret reference: synchat/prod/api

AWS Secrets Manager
  └── actual password and credentials
```

There are two common delivery shapes:

```text
Preferred for the learning path:
Secrets Manager → CSI volume → file in the Pod

Compatibility option:
Secrets Manager → CSI driver syncs a Kubernetes Secret → env/volume reference
```

The second option is convenient for applications that only understand
environment variables, but it places a copy in a Kubernetes Secret. Kubernetes
Secret objects still require access control and encryption-at-rest; using AWS
Secrets Manager does not make the Kubernetes copy disappear.

Secret rotation also has to be designed. Secrets Manager can rotate the value,
but an already-running application may need the mounted file to refresh or may
need a restart/reload to pick up the new value. Therefore production design
must answer:

```text
Secret rotates
      │
      ├── Does the mounted file refresh?
      ├── Does the application reread the file?
      └── If not, who safely restarts the workload?
```

For Synchat, the intended separation is:

```text
Web
  └── no database secret

API
  └── database / application secrets

Crawler
  └── only crawler-specific credentials, if needed
```

This keeps secret access aligned with the workload that actually needs it.

### Secrets terminology from first principles

#### What is a secret?

A secret is sensitive data that an application needs while running:

```text
Database password
JWT signing key
Third-party API token
OAuth client secret
Encryption key
```

This is different from ordinary configuration:

```text
Ordinary configuration
  LOG_LEVEL=info
  API_PORT=8080

Sensitive configuration
  DATABASE_PASSWORD=...
  OPENAI_API_KEY=...
```

Both are configuration, but sensitive configuration needs stronger storage,
access control, auditing, rotation, and handling rules.

#### What is AWS Secrets Manager?

AWS Secrets Manager is an AWS service that stores sensitive values and exposes
them through an authenticated API.

```text
Without a secret manager:

Git ──► Helm values ──► Pod environment ──► application
          │
          └── password can leak into Git, logs, state, or rendered YAML

With Secrets Manager:

Git ──► secret name/reference only

AWS Secrets Manager ──► authorized workload ──► application
```

Secrets Manager can also support versions and rotation workflows. It does not
automatically grant every Pod access. An application must authenticate to AWS,
and IAM must authorize access to a particular secret.

#### What is a Kubernetes ServiceAccount?

A Kubernetes `ServiceAccount` is an identity assigned to a Pod. It is not:

```text
not a Kubernetes Service
not an API service
not an end-user account
not a database user
```

The relationship is:

```text
Deployment
  └── creates Pod
        └── uses ServiceAccount: synchat-api
```

The ServiceAccount tells Kubernetes and integrated platform components:

```text
“This Pod is running as the synchat-api workload identity.”
```

A Deployment might therefore contain:

```yaml
spec:
  template:
    spec:
      serviceAccountName: synchat-api
```

This does not give the Pod AWS permissions by itself. It gives the Pod a
Kubernetes identity that can be mapped to an AWS IAM role.

#### What is an IAM role in this flow?

An IAM role is a set of AWS permissions that can be assumed temporarily by a
trusted identity.

```text
IAM role
  ├── trust policy: who may assume this role?
  └── permission policy: what may the role do?
```

For the Synchat API:

```text
Trust policy
  └── allows EKS Pod Identity to use the role

Permission policy
  └── allows secretsmanager:GetSecretValue
      only for synchat/prod/api
```

The application should not receive an AWS access key and secret key in its
environment. EKS provides temporary credentials for the IAM role associated
with the workload identity. AWS SDKs can use those credentials through their
normal credential lookup chain. See [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).

#### What is EKS Pod Identity?

EKS Pod Identity is the bridge between a Kubernetes ServiceAccount and an AWS
IAM role.

```text
Kubernetes side                         AWS side

ServiceAccount                         IAM role
synchat-api                             synchat-api-secrets-role
       │                                      │
       └──────── Pod Identity association ────┘
```

The runtime flow is:

```text
1. API Pod starts with ServiceAccount: synchat-api
2. EKS recognizes the Pod Identity association
3. EKS provides temporary AWS credentials for the mapped IAM role
4. The secret provider uses those credentials
5. Secrets Manager checks the IAM permissions
6. The secret is returned only if the policy allows it
```

The critical security boundary is:

```text
Web ServiceAccount  ── no association ──► no API secret
Crawler ServiceAccount ─ limited role ──► crawler secrets only
API ServiceAccount ───── API role ──────► API secret only
```

#### What is a CSI driver?

CSI means Container Storage Interface. It is a standard interface that lets a
storage plugin make external data appear inside a Pod as a mounted volume.

```text
Pod
  └── volume mount: /mnt/secrets
          ▲
          │
    CSI driver
          ▲
          │
External provider: AWS Secrets Manager
```

The CSI driver does not mean “a database.” It is a Kubernetes storage
integration mechanism. The same general pattern can expose block storage,
filesystems, or external secret values.

#### What is the Secrets Store CSI Driver?

The Secrets Store CSI Driver is a Kubernetes component that lets a Pod declare:

```text
“When this Pod starts, obtain these external objects and mount them as files.”
```

The driver itself is not AWS-specific. It uses a provider plugin to talk to a
particular external system.

```text
Kubernetes Pod
      │
      ▼
Secrets Store CSI Driver
      │
      ├── AWS provider → AWS Secrets Manager
      ├── another provider → another secret system
      └── another provider → another external vault
```

#### What is ASCP?

ASCP means AWS Secrets and Configuration Provider. It is the AWS provider used
with the Secrets Store CSI Driver. It knows how to retrieve objects from AWS
Secrets Manager and Systems Manager Parameter Store.

```text
Secrets Store CSI Driver = Kubernetes integration mechanism
ASCP                         = AWS-specific provider
Secrets Manager              = AWS storage service
```

Together:

```text
Pod volume request
        │
        ▼
CSI Driver
        │ delegates to
        ▼
ASCP
        │ authenticates using Pod Identity
        ▼
AWS Secrets Manager
```

#### What is a SecretProviderClass?

`SecretProviderClass` is a Kubernetes custom resource describing which external
secret the CSI driver should retrieve and how it should appear in the Pod.

It is a reference, not the secret value:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: synchat-api-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: synchat/prod/api
        objectType: secretsmanager
```

The object says:

```text
Provider: AWS
Secret name: synchat/prod/api
Secret value: not present in this YAML
```

The Pod then declares a CSI volume using that `SecretProviderClass`:

```text
API Deployment
  └── volume: secret-store
        └── SecretProviderClass: synchat-api-secrets
              └── mounts files into /mnt/secrets
```

#### What does the application finally see?

The application sees a normal file, for example:

```text
/mnt/secrets/database-url
/mnt/secrets/api-key
```

The application does not need to know that the value came from:

```text
AWS Secrets Manager
EKS Pod Identity
IAM
CSI
ASCP
```

That infrastructure is hidden behind the mounted file interface.

#### Complete end-to-end diagram

```text
                         CONTROL PLANE / PLATFORM

Terraform ──creates──► IAM role
                         │
Terraform ──creates──► Pod Identity association
                         │
Helm ──creates───────► ServiceAccount: synchat-api
                         │
Helm ──creates───────► SecretProviderClass

                         RUNTIME

API Deployment
      │
      ├── uses ServiceAccount: synchat-api
      └── mounts CSI volume: /mnt/secrets
                │
                ▼
       Secrets Store CSI Driver
                │
                ▼
                ASCP
                │ uses temporary credentials from Pod Identity
                ▼
       AWS Secrets Manager
                │
                ▼
       authorized secret value
                │
                ▼
       /mnt/secrets/database-url
```

The authorization decision happens before the value reaches the Pod:

```text
Is this Pod using the expected ServiceAccount?
        │ no → deny
        ▼ yes
Does its IAM role allow GetSecretValue?
        │ no → deny
        ▼ yes
Does the policy allow this exact secret ARN?
        │ no → deny
        ▼ yes
Return the secret value
```

This is why the ServiceAccount, Pod Identity association, IAM role, policy,
CSI driver, ASCP, and Secrets Manager all appear in one design. Each component
has one responsibility; none of them is the whole secret-management system.

### Terraform implementation summary: API Pod reading one secret

The real-AWS implementation is split into these Terraform objects:

```text
aws_secretsmanager_secret
  └── creates the secret container; no plaintext value in Terraform

data.aws_iam_policy_document.api_secrets_trust
  └── builds the trust-policy JSON

aws_iam_role.api_secrets
  └── creates the IAM role and receives the trust policy

data.aws_iam_policy_document.api_secrets_permissions
  └── builds the least-privilege permission JSON

aws_iam_role_policy.api_secrets
  └── attaches the permission policy to the role

aws_eks_pod_identity_association.api
  └── maps synchat-dev/synchat-api to the IAM role
```

Representative configuration:

```hcl
resource "aws_secretsmanager_secret" "api_database" {
  name = "synchat/prod/api/database"
}

data "aws_iam_policy_document" "api_secrets_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "api_secrets" {
  name               = "synchat-prod-api-secrets"
  assume_role_policy = data.aws_iam_policy_document.api_secrets_trust.json
}

data "aws_iam_policy_document" "api_secrets_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.api_database.arn]
  }
}

resource "aws_iam_role_policy" "api_secrets" {
  role   = aws_iam_role.api_secrets.id
  policy = data.aws_iam_policy_document.api_secrets_permissions.json
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "synchat-dev"
  service_account = "synchat-api"
  role_arn        = aws_iam_role.api_secrets.arn
}
```

The trust and permission policies are separate concepts:

```text
Trust policy
  └── Principal: pods.eks.amazonaws.com
      Action: sts:AssumeRole
      Meaning: who may use the role?

Permission policy
  └── Action: secretsmanager:GetSecretValue
      Resource: one secret ARN
      Meaning: what may the role do?
```

The Helm chart must create a ServiceAccount named `synchat-api` in namespace
`synchat-dev` and set `serviceAccountName: synchat-api` on the API Deployment.
The Terraform Pod Identity association does not create that Kubernetes object;
it only maps the expected identity to the IAM role.

The inline-policy attachment above uses `aws_iam_role_policy`. A reusable
alternative is `aws_iam_policy` plus `aws_iam_role_policy_attachment`:

```text
aws_iam_role_policy
  └── policy belongs directly to one role

aws_iam_policy + aws_iam_role_policy_attachment
  └── standalone policy can be attached to multiple roles
```

Runtime flow:

```text
API Pod → synchat-api ServiceAccount
        → EKS Pod Identity association
        → api_secrets IAM role
        → GetSecretValue permission
        → one authorized Secrets Manager secret
```

### Where the `GetSecretValue` permission is defined

It belongs to the role's permission policy, not its trust policy:

```hcl
data "aws_iam_policy_document" "api_secrets_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [aws_secretsmanager_secret.api_database.arn]
  }
}

resource "aws_iam_role_policy" "api_secrets" {
  role   = aws_iam_role.api_secrets.id
  policy = data.aws_iam_policy_document.api_secrets_permissions.json
}
```

The two policies work together:

```text
Trust policy
  └── EKS Pod Identity may assume the role

Permission policy
  └── the assumed role may call GetSecretValue
      for one specific secret ARN
```

### Editing a secret in the AWS Console

An operator can create or edit a Secrets Manager secret in the AWS Console.
AWS creates a new secret version when the secret value is changed; the newest
version receives the `AWSCURRENT` staging label and the previous version can be
identified as `AWSPREVIOUS`. See [Modify an AWS Secrets Manager
secret](https://docs.aws.amazon.com/secretsmanager/latest/userguide/manage_update-secret.html).

Whether that change is safe depends on who owns each part:

```text
Terraform owns:
  ├── secret metadata/name/tags
  ├── IAM roles and policies
  └── Pod Identity association

Secrets Manager process owns:
  └── actual secret value and rotation

Helm / Argo CD owns:
  └── Kubernetes references to the secret
```

If Terraform creates only `aws_secretsmanager_secret` and does not manage a
`secret_string` or `aws_secretsmanager_secret_version`, editing the value in
the Console does not conflict with Terraform's desired configuration. This is
the preferred separation for the learning design.

If Terraform manages the plaintext value, a Console edit creates a conflict:

```text
Terraform configuration says: value A
AWS Console contains:         value B
```

Terraform can detect this drift and a later apply may overwrite the manually
edited value. It may also expose the value through Terraform state, so we avoid
that pattern for production credentials. Terraform detects out-of-band changes
through refresh and reports them during planning; see [Terraform resource
drift](https://developer.hashicorp.com/terraform/tutorials/state/resource-drift).

Argo CD is not required to edit the AWS secret value:

```text
Direct Secrets Manager / rotation process
  └── changes the AWS secret value

Argo CD
  └── deploys Kubernetes references and application manifests
```

If using an External Secrets Operator, Argo CD can manage an
`ExternalSecret` manifest while the operator reads AWS Secrets Manager and
creates/updates a Kubernetes Secret. If using the Secrets Store CSI Driver,
Argo CD can manage the `SecretProviderClass` and Deployment volume reference;
the CSI provider retrieves the value at Pod runtime.

### External Secrets versus Secrets Store CSI

These are two different delivery mechanisms for the same source of truth:

```text
Source of truth in both designs:

AWS Secrets Manager
```

#### External Secrets Operator

The External Secrets Operator is a controller running in Kubernetes. A
controller watches a custom resource called `ExternalSecret` and continually
reconciles it into a normal Kubernetes `Secret`.

```text
Argo CD
  └── applies ExternalSecret manifest
          │
          ▼
External Secrets Operator
  └── reads AWS Secrets Manager
          │
          ▼
Kubernetes Secret
  └── stores a synchronized copy in the Kubernetes API
          │
          ▼
Synchat API Pod
  └── reads the Kubernetes Secret as env vars or a volume
```

Example shape:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: synchat-api-database
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: synchat-api-database
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: synchat/prod/api/database
```

The YAML contains the reference `synchat/prod/api/database`, not the password.
The operator uses its own AWS workload identity to read the value.

The API can then consume the generated Kubernetes Secret:

```yaml
envFrom:
  - secretRef:
      name: synchat-api-database
```

The important property is that a copy now exists as a Kubernetes Secret:

```text
AWS Secrets Manager value
          │
          ▼
Kubernetes Secret copy
          │
          ▼
API Pod
```

Therefore Kubernetes RBAC, encryption at rest, access logging, and namespace
permissions must also be configured correctly.

#### Secrets Store CSI Driver

The Secrets Store CSI Driver uses a `SecretProviderClass` to describe what the
Pod should mount. The provider retrieves the value when the Pod requests the
volume.

```text
Argo CD
  ├── applies SecretProviderClass
  └── applies Deployment with CSI volume
          │
          ▼
Secrets Store CSI Driver
  └── invokes the AWS provider (ASCP)
          │
          ▼
AWS Secrets Manager
          │
          ▼
Secret mounted as a file inside the API Pod
```

Example shape:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: synchat-api-database
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: synchat/prod/api/database
        objectType: secretsmanager
```

The Deployment references it through a CSI volume:

```yaml
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: synchat-api-database

volumeMounts:
  - name: secrets-store
    mountPath: /mnt/secrets
    readOnly: true
```

The application reads a file such as:

```text
/mnt/secrets/database-url
```

By default, CSI is a mounted-file mechanism. It does not necessarily create a
Kubernetes `Secret`. A separate sync option can create one when an application
requires environment variables, but that reintroduces a Kubernetes copy.

#### What exactly does Argo CD manage?

Argo CD manages the declarative Kubernetes objects stored in Git:

```text
Git
  ├── ExternalSecret or SecretProviderClass
  ├── ServiceAccount
  └── Deployment
          │
          ▼
Argo CD applies these manifests
```

Argo CD does not normally store or apply the plaintext AWS value. Runtime
components retrieve it using their AWS identity:

```text
External Secrets path:
Argo CD → ExternalSecret → operator → Kubernetes Secret → Pod

CSI path:
Argo CD → SecretProviderClass + Deployment → CSI provider → mounted file
```

#### Comparison

```text
External Secrets Operator
  ├── creates a Kubernetes Secret copy
  ├── convenient for env vars and normal Secret references
  ├── operator continuously synchronizes changes
  └── requires careful Kubernetes Secret protection

Secrets Store CSI Driver
  ├── mounts the external value as a file
  ├── avoids a Kubernetes Secret by default
  ├── good for file-based secret consumption
  └── application must read files or use the sync option
```

For Synchat, the choice depends on the API's configuration contract:

```text
API can read files
  └── CSI mounted file is a clean design

API requires environment variables
  └── External Secrets is simpler
      or CSI with Kubernetes Secret synchronization
```

### Synchat implementation: Secrets Store CSI on real AWS

The Synchat chart now contains an opt-in CSI integration. It is disabled by
default so that a normal chart install does not fail when the CSI driver has
not yet been installed.

```yaml
secrets:
  enabled: false
  provider: aws
  secretProviderClassName: synchat-api-database
  objectName: synchat/prod/api/database
  mountPath: /mnt/secrets
```

When enabled, the chart creates this runtime path:

```text
Synchat API Deployment
  ├── ServiceAccount: synchat-api
  ├── SecretProviderClass: synchat-api-database
  └── CSI volume mounted at /mnt/secrets
          │
          ▼
Secrets Store CSI Driver
          │
          ▼
AWS provider (ASCP)
          │
          ▼
AWS Secrets Manager: synchat/prod/api/database
```

The chart changes are:

```text
values.yaml
  └── secret name, mount path, and feature flag

api-secretproviderclass.yaml
  └── tells the AWS provider which secret to retrieve

api-deployment.yaml
  └── mounts the CSI volume into the API container
```

The chart does not contain the secret value and does not create the AWS IAM
role. Those belong to the platform layer.

#### Real-AWS setup sequence

The implementation has platform prerequisites and application configuration.
Complete them in this order:

```text
1. EKS platform prerequisites
2. AWS secret and IAM permissions
3. Kubernetes workload identity
4. CSI driver and AWS provider
5. Synchat Helm configuration
6. Runtime verification
```

#### 1. Enable the EKS Pod Identity Agent

Manage the Pod Identity Agent as an EKS add-on through Terraform:

```hcl
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
}
```

This is cluster infrastructure. It is not part of the Synchat chart.

```text
EKS Pod Identity Agent
  └── allows EKS to provide AWS role credentials to selected Pod identities
```

#### 2. Create the AWS secret and IAM permissions

Create the secret in AWS Secrets Manager using the stable name:

```text
synchat/prod/api/database
```

For learning, the value can be created or edited in the AWS Console. In a
production team, use the approved secret bootstrap or rotation process.

Create an IAM role whose trust policy allows the EKS Pod Identity service, then
attach a permission policy containing only:

```text
secretsmanager:GetSecretValue
        │
        └── Resource: ARN of synchat/prod/api/database
```

Do not grant the API role `secretsmanager:*` or access to every secret.

#### 3. Create the workload identity mapping

The Helm chart creates this Kubernetes identity:

```text
Namespace:      synchat-dev
ServiceAccount: synchat-api
```

Terraform maps it to the IAM role:

```hcl
resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "synchat-dev"
  service_account = "synchat-api"
  role_arn        = aws_iam_role.api_secrets.arn
}
```

This resource does not create the ServiceAccount. The Helm chart creates it;
the names must match exactly.

#### 4. Install the CSI driver and AWS provider

Install these as cluster/platform components, preferably through Argo CD once
GitOps is introduced:

```text
Secrets Store CSI Driver
  └── generic Kubernetes CSI integration

AWS provider for the CSI Driver (ASCP)
  └── knows how to retrieve Secrets Manager values
```

They are not application containers and should not be copied into the Synchat
chart. The driver and provider must be installed before enabling the Synchat
secret volume.

#### 5. Enable the Synchat integration

Use an environment-specific values file, for example:

```yaml
secrets:
  enabled: true
  provider: aws
  secretProviderClassName: synchat-api-database
  objectName: synchat/prod/api/database
  mountPath: /mnt/secrets
```

Then the rendered API Deployment contains:

```yaml
volumeMounts:
  - name: api-secrets
    mountPath: /mnt/secrets
    readOnly: true
```

and:

```yaml
volumes:
  - name: api-secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: synchat-api-database
```

The `SecretProviderClass` refers to the AWS secret by name:

```yaml
parameters:
  usePodIdentity: "true"
  objects: |
    - objectName: "synchat/prod/api/database"
      objectType: "secretsmanager"
```

#### 6. Verify the runtime path

Verification should follow the path from infrastructure to application:

```text
EKS Pod Identity Agent healthy
        │
        ▼
CSI driver and ASCP healthy
        │
        ▼
ServiceAccount and Pod Identity association match
        │
        ▼
SecretProviderClass exists
        │
        ▼
API Pod starts successfully
        │
        ▼
Secret file is mounted at /mnt/secrets
```

If the API Pod cannot start, inspect the Pod events and CSI provider logs. The
most common causes are:

```text
Wrong namespace or ServiceAccount name
Wrong IAM role in the Pod Identity association
Missing GetSecretValue permission
Wrong secret name or region
CSI driver not installed
ASCP not installed
SecretProviderClass created before the provider exists
```

The current Synchat application does not yet read a database secret from
`/mnt/secrets`; the chart change establishes the production delivery path.
Application code must be changed separately to read the required file before
the secret affects database connectivity.

### CSI Driver versus ASCP

These components are often shown together because they perform different parts
of one operation:

```text
CSI Driver
  └── Kubernetes-side volume mechanism

ASCP
  └── AWS-side secret retrieval provider
```

CSI means Container Storage Interface. It is a standard contract used by
Kubernetes to attach or mount external storage-like data into a Pod. The CSI
Driver understands Kubernetes operations such as:

```text
Pod requests a volume
        │
        ▼
Kubelet asks the CSI Driver to mount it
        │
        ▼
CSI Driver prepares the mount path
        │
        ▼
The container sees a normal directory
```

The CSI Driver does not inherently know how to call AWS Secrets Manager. It
delegates the provider-specific work.

ASCP means AWS Secrets and Configuration Provider. It is the AWS plugin that
knows how to:

```text
Authenticate using the Pod's AWS identity
Call Secrets Manager
Interpret the SecretProviderClass parameters
Return the selected secret object
```

The combined runtime sequence is:

```text
1. API Pod requests the CSI volume
2. CSI Driver receives the Kubernetes mount request
3. CSI Driver invokes the AWS provider (ASCP)
4. ASCP uses EKS Pod Identity credentials
5. ASCP calls Secrets Manager GetSecretValue
6. IAM checks the role and secret ARN
7. ASCP returns the authorized value
8. CSI Driver makes it available at /mnt/secrets
9. API container reads a normal file
```

```text
Kubernetes responsibility                 AWS responsibility

Pod / Deployment                          Secrets Manager
SecretProviderClass                       IAM authorization
CSI volume and mount                      Pod Identity credentials
CSI Driver
        │ invokes
        ▼
      ASCP
        │ calls
        ▼
AWS Secrets Manager
```

The `SecretProviderClass` connects the two sides:

```yaml
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: synchat/prod/api/database
        objectType: secretsmanager
```

```text
provider: aws
  └── select ASCP

objectName
  └── tell ASCP which AWS secret to retrieve

CSI volume reference
  └── tell Kubernetes which SecretProviderClass belongs to the mount
```

An analogy:

```text
CSI Driver = standard electrical socket
ASCP       = AWS-specific plug/adapter
Secret     = electricity supplied by AWS
```

The socket gives Kubernetes a standard interface. The adapter knows how to
connect that interface to AWS Secrets Manager. A different provider could use
the same CSI mechanism to retrieve secrets from another external system.

### Helm production hardening: environment-specific values

The chart now separates shared defaults from environment-specific overrides:

```text
charts/synchat/
  ├── values.yaml          shared defaults
  ├── values-dev.yaml      development overrides
  ├── values-stage.yaml    staging overrides
  └── values-prod.yaml     production overrides
```

Helm combines them in this order:

```text
values.yaml
      │ base configuration
      ▼
values-prod.yaml
      │ environment overrides
      ▼
final rendered Kubernetes manifests
```

The environment file should contain only differences. For example:

```yaml
web:
  replicas: 3

api:
  replicas: 2

secrets:
  enabled: true
```

The shared chart remains reusable, while each environment can choose its own
replica counts, hostnames, image references, secret settings, and later its
resource limits or autoscaling values.

Render a specific environment with:

```bash
helm template synchat charts/synchat \
  --namespace synchat-dev \
  --values charts/synchat/values-dev.yaml
```

For production, the same chart is rendered with `values-prod.yaml`. The chart
templates do not change between environments; only the values change.

The current files use these learning defaults:

```text
Development
  └── web 2, API 1, crawler 1, external secrets disabled

Staging
  └── web 2, API 2, crawler 1, external secrets disabled

Production
  └── web 3, API 2, crawler 2, external secrets enabled
```

Production secret delivery still requires the EKS CSI driver, ASCP, Pod
Identity Agent, IAM role, and AWS secret to exist before the production values
file is deployed.

### Helm production hardening: immutable image tags

`latest` is a mutable label. The same label can point to different image
content over time:

```text
Monday:  latest → image A
Tuesday: latest → image B

The Deployment YAML still says latest, but the running code changed.
```

Production releases should identify image content immutably, usually with a
commit SHA or release version:

```text
web:a1b2c3d
api:a1b2c3d
crawler:a1b2c3d
```

The chart already had an image tag value for each component. It now also has an
environment value and rejects `latest` outside development:

```text
environment = dev
  └── latest allowed for learning convenience

environment = stage or prod
  └── latest rejected during Helm rendering
```

This fails early:

```text
helm template with stage/prod values
        │
        ▼
latest tag detected
        │
        ▼
render fails before deployment
```

CI supplies the immutable tags at render or deployment time:

```bash
helm template synchat charts/synchat \
  --values charts/synchat/values-prod.yaml \
  --set web.image.tag="$GIT_SHA" \
  --set api.image.tag="$GIT_SHA" \
  --set crawler.image.tag="$GIT_SHA"
```

The tag should refer to an image that CI has already built, scanned, and
published. The complete delivery relationship is:

```text
Git commit SHA
      │
      ├── CI builds web/api/crawler images
      ├── CI scans images
      └── CI publishes images tagged with the SHA
                    │
                    ▼
          Helm receives the same SHA
                    │
                    ▼
             Kubernetes runs known content
```

The chart was validated in three ways:

```text
Development + latest             → renders successfully
Stage + latest                   → rejected
Stage + immutable tags           → renders successfully
```

### Helm production hardening: resource requests and limits

Each Synchat container now declares CPU and memory expectations:

```yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1
    memory: 512Mi
```

Plain meaning:

```text
Requests
  └── the minimum capacity Kubernetes should reserve for the Pod

Limits
  └── the maximum capacity the container may consume
```

CPU units:

```text
100m = 0.1 CPU core
200m = 0.2 CPU core
1    = 1 CPU core
```

Memory units such as `Mi` are Kubernetes resource quantities:

```text
256Mi = approximately 256 mebibytes
512Mi = approximately 512 mebibytes
```

Requests influence scheduling:

```text
Pod requests 200m CPU + 256Mi memory
        │
        ▼
Scheduler finds a node with that capacity available
        │
        ▼
Pod is placed on the node
```

Limits protect the node and neighboring workloads:

```text
Container uses more CPU
  └── CPU is throttled near its limit

Container exceeds its memory limit
  └── container may be terminated with an out-of-memory failure
```

Requests and limits are not performance guarantees. They are scheduling and
resource-control boundaries. Production values should come from measurements,
load tests, and observed peak behavior rather than guesses.

The shared `values.yaml` contains conservative defaults. `values-prod.yaml`
overrides them with larger production starting points:

```text
Shared defaults
  └── web/api/crawler: 100m CPU, 128Mi request, 500m CPU, 256Mi limit

Production overrides
  └── web/api/crawler: 200m CPU, 256Mi request, 1 CPU, 512Mi limit
```

This keeps resource sizing configurable without changing Deployment templates.

### How to choose requests and limits

There is no universal correct value. Use this process:

```text
1. Start with a small safe estimate
2. Run realistic traffic and background work
3. Measure CPU and memory usage
4. Add headroom for normal peaks
5. Observe restarts, throttling, and scheduling
6. Adjust the values and repeat
```

Measure each workload separately:

```text
Web
  └── browser/API traffic and concurrent users

API
  └── requests, JSON processing, database calls

Crawler
  └── crawl volume, parsing, queue behavior
```

#### Choosing a CPU request

The CPU request should approximate the CPU the container needs during normal
operation, not its absolute maximum:

```text
Normal API CPU usage: 120m
Observed normal peak: 180m
Starting request:     200m
```

If the request is too low:

```text
Scheduler thinks the Pod is cheap
        │
        ▼
Node becomes crowded
        │
        ▼
Application competes for CPU
```

If the request is too high:

```text
Scheduler reserves more CPU than needed
        │
        ▼
Fewer Pods fit on each node
        │
        ▼
Higher infrastructure cost or scheduling failures
```

#### Choosing a CPU limit

The CPU limit is the maximum CPU usage allowed by the container. It should
allow normal bursts without letting one workload consume an entire node.

```text
Normal usage: 120m
Peak burst:   450m
Starting limit: 500m or 1 CPU
```

CPU limits can cause throttling when a container reaches the limit. Therefore,
do not choose an unnecessarily low CPU limit for latency-sensitive APIs.

#### Choosing a memory request

Memory requests should cover the application's normal working set:

```text
Normal memory: 180Mi
Peak observed: 230Mi
Starting request: 256Mi
```

If the request is too low, Kubernetes may place too many memory-consuming Pods
on one node. If a node experiences memory pressure, Pods with lower requests or
lower quality-of-service protection may be evicted first.

#### Choosing a memory limit

The memory limit should cover normal peaks and a reasonable safety margin:

```text
Normal memory: 180Mi
Peak observed: 230Mi
Headroom:       80Mi
Starting limit:  320Mi
```

Memory is different from CPU:

```text
CPU exceeds limit
  └── usually throttled

Memory exceeds limit
  └── container may be killed with OOMKilled
```

Do not use an extremely small memory limit to hide a memory leak. Investigate
whether the process is growing continuously before increasing the limit.

#### A practical starting table

For learning, the chart uses starting points rather than claiming these are
the final production values:

```text
Workload   CPU request   Memory request   CPU limit   Memory limit
Web        100m          128Mi            500m        256Mi
API        100m          128Mi            500m        256Mi
Crawler    100m          128Mi            500m        256Mi
```

Production overrides currently start at a larger level, but they must be
validated with real measurements. The correct workflow is:

```text
Deploy with starting values
        │
        ▼
Generate representative traffic
        │
        ▼
Observe CPU, memory, latency, restarts, and OOM events
        │
        ▼
Tune requests and limits
        │
        ▼
Use the measured values in the production values file
```

### The identity chain: ServiceAccount → Pod Identity → IAM role

Start with the question each layer answers:

```text
Kubernetes ServiceAccount
  “Which workload is this?”

EKS Pod Identity association
  “Which AWS role should this workload use?”

IAM role
  “Which AWS actions may it perform?”

IAM permission policy
  “Which exact resources may those actions access?”
```

#### 1. The Pod uses a named ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: synchat-api
  namespace: synchat-dev
```

The Deployment explicitly selects it:

```yaml
spec:
  template:
    spec:
      serviceAccountName: synchat-api
```

The result is:

```text
Deployment
  └── API Pod
        └── identity = synchat-api
```

If `serviceAccountName` is omitted, Kubernetes normally uses the namespace's
`default` ServiceAccount. That is usually too broad and ambiguous for a
production workload because unrelated Pods may share it.

#### 2. EKS maps that identity to an IAM role

An EKS Pod Identity association is conceptually:

```text
Cluster:        synchat-eks
Namespace:      synchat-dev
ServiceAccount: synchat-api
        │
        ▼
IAM role:       synchat-api-secrets-role
```

The Terraform resource has this general shape:

```hcl
resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "synchat-dev"
  service_account = "synchat-api"
  role_arn        = aws_iam_role.api_secrets.arn
}
```

This association does not grant arbitrary AWS permissions. It only tells EKS
which role belongs to this workload identity.

#### 3. The IAM role trusts EKS Pod Identity

The role's trust policy answers:

```text
Who may assume this role?
```

For EKS Pod Identity, the trusted AWS service principal is conceptually:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": [
    "sts:AssumeRole",
    "sts:TagSession"
  ]
}
```

This means the EKS Pod Identity service may provide credentials for the role.
It does not yet say that the role may read Secrets Manager.

#### 4. The permission policy grants the AWS action

The permission policy answers:

```text
What may the assumed role do?
```

For the API's database secret:

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:...:secret:synchat/prod/api-*"
}
```

The complete authorization check is:

```text
API Pod uses synchat-api ServiceAccount
        │
        ▼
Pod Identity maps it to api-secrets-role
        │
        ▼
Trust policy allows Pod Identity to use the role
        │
        ▼
Permission policy allows GetSecretValue
        │
        ▼
Resource matches synchat/prod/api
        │
        ▼
Secret Manager returns the value
```

If any step fails, access fails:

```text
Wrong ServiceAccount       → no association
No association             → no workload role
Wrong trust policy         → role cannot be assumed
Missing action             → API call is denied
Wrong secret ARN           → resource authorization is denied
```

#### Why the ServiceAccount matters

The IAM role is not attached to every Pod in the cluster:

```text
Cluster
  ├── API Pod
  │     └── ServiceAccount: synchat-api
  │           └── API secrets role
  │
  ├── Web Pod
  │     └── ServiceAccount: synchat-web
  │           └── no database-secret role
  │
  └── Crawler Pod
        └── ServiceAccount: synchat-crawler
              └── crawler-specific role, if required
```

This is workload-level least privilege. A compromised Web Pod should not
automatically inherit the API's database permissions merely because both Pods
run in the same namespace or on the same worker node.

#### ServiceAccount versus IAM user credentials

Avoid this pattern:

```text
AWS access key + secret key
        │
        ▼
Helm values / Kubernetes Secret / Pod environment
```

Prefer this pattern:

```text
ServiceAccount
        │
        ▼
EKS Pod Identity
        │
        ▼
short-lived AWS credentials
```

The application uses the AWS SDK's normal credential chain. The developer does
not copy a long-lived AWS access key into the application configuration.

This is the same identity principle used by AWS services elsewhere:

```text
Human or workload identity
        │
        ▼
Assume an IAM role
        │
        ▼
Receive temporary credentials
        │
        ▼
Call only authorized AWS APIs
```

### Testing resource values on real AWS

Do not discover resource mistakes for the first time in production. Use a
staging namespace or staging EKS cluster with the same chart and representative
image versions.

```text
Build immutable images
        │
        ▼
Deploy to staging EKS
        │
        ▼
Generate representative traffic
        │
        ▼
Observe scheduling, CPU, memory, latency, and restarts
        │
        ▼
Tune values and repeat
        │
        ▼
Promote the tested image and values to production
```

#### 1. Render and inspect before deployment

```bash
helm template synchat charts/synchat \
  --namespace synchat-stage \
  --values charts/synchat/values-stage.yaml \
  --set web.image.tag="$GIT_SHA" \
  --set api.image.tag="$GIT_SHA" \
  --set crawler.image.tag="$GIT_SHA" \
  > rendered-stage.yaml
```

This catches Helm and values mistakes before Kubernetes is changed.

#### 2. Deploy to staging EKS

```bash
helm upgrade --install synchat charts/synchat \
  --namespace synchat-stage \
  --create-namespace \
  --values charts/synchat/values-stage.yaml \
  --set web.image.tag="$GIT_SHA" \
  --set api.image.tag="$GIT_SHA" \
  --set crawler.image.tag="$GIT_SHA" \
  --wait \
  --timeout 10m
```

`--wait` waits for resources to become ready. It does not prove that resource
values are correct under load.

#### 3. Confirm scheduling and rollout

```bash
kubectl get pods -n synchat-stage
kubectl describe pod <api-pod> -n synchat-stage
kubectl get events -n synchat-stage --sort-by=.lastTimestamp
```

Look for `Pending`, `Insufficient cpu`, `Insufficient memory`,
`CrashLoopBackOff`, and `OOMKilled`.

#### 4. Generate realistic traffic

Use a controlled load-testing tool such as k6, Locust, or an internal test
client. Test concurrency and duration, not only one successful request:

```text
Web       └── concurrent browser/API requests
API       └── request rate plus database calls
Crawler   └── realistic crawl and parsing workload
```

#### 5. Observe and tune

For a quick check:

```bash
kubectl top pods -n synchat-stage
kubectl top pods -n synchat-stage --containers
```

In production, use a historical metrics platform such as Amazon Managed
Service for Prometheus, CloudWatch Container Insights, or the organization's
approved observability system. Record CPU, memory, latency, errors, restarts,
OOM events, throttling, and pending Pods.

```text
CPU below request most of the time
  └── request may be too high

CPU repeatedly hits limit and latency rises
  └── raise the limit or optimize the application

Memory near limit
  └── investigate growth, then add headroom if appropriate

Pod cannot schedule
  └── request does not fit available node capacity
```

Promote the same tested combination of image tags, chart version, values, and
resource settings. Do not rebuild the image between staging and production.

### Metrics versus profiling

Metrics tell you how much resource the workload uses:

```text
CPU:     180m
Memory:  220Mi
Latency: 300ms
Errors:  2%
```

Profiling tells you why the application uses that resource:

```text
CPU profile
  └── which functions consume CPU?

Memory profile
  └── which objects consume memory?

Flame graph
  └── which call paths dominate execution time?
```

The investigation usually works in this order:

```text
Metrics show high API CPU
        │
        ▼
Profiler identifies expensive code path
        │
        ▼
Developer optimizes the code or query
        │
        ▼
Metrics confirm the improvement
```

Typical tool categories include:

```text
Kubernetes / platform metrics
  └── Prometheus, Grafana, CloudWatch Container Insights

Application profiling
  ├── language-specific CPU and memory profilers
  ├── runtime profilers
  └── continuous profiling platforms such as Pyroscope or Parca

Load testing
  └── k6, Locust, or an internal performance client
```

Profiling is not required for every deployment. Use it when metrics show a
problem that resource changes alone will not explain:

```text
Use metrics first
  └── decide whether the Pod needs more CPU or memory

Use profiling next
  └── find the code, query, serialization, or loop causing the usage
```

Profiling in production should be controlled because it can add overhead and
may expose sensitive information in traces or stack data. A common approach is
to profile staging under realistic load, then enable limited or sampled
continuous profiling in production for important services.

### Helm production hardening: health probes

The Synchat chart now supports startup, liveness, and readiness probes for all
three workloads. Because this repository does not contain confirmed Synchat
health endpoints, the initial implementation uses TCP probes on the named
`http` container port.

```text
startupProbe
  └── has the process finished starting?

livenessProbe
  └── is the process still alive?

readinessProbe
  └── should the Service send traffic to this Pod?
```

The current chart configuration is:

```yaml
probes:
  enabled: true
  startup:
    periodSeconds: 5
    failureThreshold: 30
  liveness:
    periodSeconds: 10
    failureThreshold: 3
  readiness:
    periodSeconds: 5
    failureThreshold: 3
```

The resulting Kubernetes configuration checks whether port `http` accepts a
TCP connection:

```yaml
startupProbe:
  tcpSocket:
    port: http

livenessProbe:
  tcpSocket:
    port: http

readinessProbe:
  tcpSocket:
    port: http
```

The startup sequence is:

```text
Container starts
      │
      ▼
Startup probe runs
      │ fails while starting
      └── liveness is not used yet
      │ passes
      ▼
Liveness and readiness probes run
      │
      ├── readiness fails → remove Pod from Service endpoints
      └── liveness fails   → restart the container
```

TCP probes are a safe first step, but they only prove that something is
listening on the port. They do not prove that the application can answer
requests or reach its dependencies.

The stronger production design is to expose application-owned endpoints, for
example:

```text
/livez
  └── process is alive; usually does not check dependencies

/readyz
  └── process can serve traffic; may check required dependencies
```

Then the chart can use HTTP probes. Do not make liveness depend on every
external dependency: a temporary database outage should normally make the Pod
unready, not cause every replica to restart simultaneously.

Probe configuration must be tested under:

```text
normal startup
slow startup
temporary dependency failure
application deadlock
application process crash
rolling deployment
```

The chart was linted and rendered successfully with all three TCP probe types.
Runtime behavior still needs verification on a real staging EKS deployment.

### Helm production hardening: HorizontalPodAutoscaler

An HPA changes the number of Pod replicas based on observed metrics:

```text
CPU usage rises
      │
      ▼
HPA increases API replicas
      │
      ▼
Service spreads traffic across more Pods
```

The Synchat chart now has an optional CPU-based HPA for the API:

```yaml
api:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
```

The HPA targets the API Deployment:

```text
HPA: synergychat-api
  └── scales Deployment: synergychat-api
        └── creates or removes API Pods
```

The API's CPU request is important because a utilization target is calculated
relative to the request:

```text
CPU request: 200m
HPA target:  70%

Average usage near 140m per Pod
  └── approximately 70% of the request
```

The HPA does not create capacity from nothing. The cluster must have room for
new Pods, or the cluster's node autoscaling mechanism must add capacity:

```text
HPA scales Pods
        │
        ▼
Scheduler places Pods
        │
        ├── node has capacity → Pod starts
        └── node is full       → Pod remains Pending
                                  until capacity appears
```

HPA is appropriate for request-driven workloads such as the API. A crawler may
need a queue-depth or oldest-job metric instead of CPU because CPU usage may
not represent the amount of work waiting to be processed.

The chart keeps HPA disabled in development and enables the initial API policy
in production values. Runtime HPA behavior still requires a metrics API and
must be tested under representative staging traffic.

### Helm production hardening: PodDisruptionBudget

A PodDisruptionBudget protects a minimum level of availability during planned
disruptions:

```text
Node drain / cluster upgrade
          │
          ▼
Kubernetes wants to evict Pods
          │
          ▼
PDB limits how many matching Pods may be unavailable
```

The production values enable PDBs for Web and API:

```yaml
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
```

With two API replicas:

```text
API replicas: 2
maxUnavailable: 1

At least one API Pod should remain available during a voluntary disruption.
```

The PDB selects Pods using the same application label as the Deployment:

```yaml
selector:
  matchLabels:
    app: synergychat-api
```

The selector must match the Deployment's Pod labels. A PDB with the wrong
selector protects nothing useful.

PDBs apply mainly to voluntary disruptions:

```text
PDB helps with:
  ├── node drain
  ├── cluster maintenance
  └── planned node replacement

PDB does not prevent:
  ├── application crashes
  ├── OOMKilled containers
  ├── hardware failure
  └── a node disappearing unexpectedly
```

Do not configure `maxUnavailable: 0`; Kubernetes would be unable to make
planned progress when it needs to evict a Pod. Also ensure the workload has
enough replicas. A PDB cannot create a replacement Pod or add node capacity.

The chart keeps PDBs disabled in development and enables them for the
production Web and API workloads. Runtime behavior still needs verification
during a controlled staging node-drain test.

### Helm production hardening: rolling updates

A rolling update replaces old Pods gradually instead of stopping the whole
Deployment at once:

```text
Old Pods:  A  B  C
                │ release new image
                ▼
Start new Pod:  D
Wait for D ready
Remove old Pod: A
Start new Pod:  E
Wait for E ready
Remove old Pod: B
```

The Synchat Deployments now explicitly use:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Plain meaning:

```text
maxUnavailable: 0
  └── do not intentionally take an existing ready Pod away first

maxSurge: 1
  └── create at most one extra replacement Pod during the rollout
```

The rollout therefore needs temporary capacity:

```text
Desired replicas: 3
Normal:           3 Pods
During rollout:   up to 4 Pods
After rollout:    3 new Pods
```

Readiness probes are essential here. Kubernetes should remove an old Pod only
after the replacement Pod is considered ready:

```text
New Pod starts
      │
      ▼
Readiness probe passes
      │
      ▼
New Pod receives traffic
      │
      ▼
Old Pod is removed
```

`maxUnavailable: 0` is a safety preference, not a guarantee that a rollout
can always complete. If there is no spare node capacity, the new Pod may stay
Pending. If its readiness probe never passes, the old Pod remains and the
rollout pauses.

The difference from `maxUnavailable: 1` with three desired replicas is:

```text
maxUnavailable: 0
  └── keep 3 available
      create a replacement first
      requires temporary capacity

maxUnavailable: 1
  └── may temporarily have only 2 available
      remove one old Pod first
      needs less temporary capacity
```

```text
maxUnavailable: 0
  3 old → 3 old + 1 new → 2 old + 1 new → 1 old + 2 new → 3 new

maxUnavailable: 1
  3 old → 2 old → 2 old + 1 new → 1 old + 2 new → 3 new
```

Therefore `maxUnavailable: 0` favors availability, while
`maxUnavailable: 1` favors using less temporary capacity. The right choice
depends on traffic requirements and available node capacity.

### Helm rollback

Helm keeps a revision history for each release. An upgrade creates a new
revision:

```text
synchat revision 1 → first release
synchat revision 2 → image a1b2c3d
synchat revision 3 → image bad9999
```

If revision 3 is unhealthy, Helm can restore revision 2:

```text
Healthy revision 2
        │ upgrade
        ▼
Broken revision 3
        │ rollback
        ▼
Revision 4, rendered from revision 2 configuration
```

A rollback creates a new history entry; it does not erase history.

Useful commands in a staging EKS cluster:

```bash
helm history synchat --namespace synchat-stage
helm status synchat --namespace synchat-stage
helm rollback synchat 2 \
  --namespace synchat-stage \
  --wait \
  --timeout 10m
helm status synchat --namespace synchat-stage
```

The number `2` is the known-good revision from `helm history`. Never guess it.
Inspect the revision history and release status first.

Rollback restores Kubernetes release configuration such as:

```text
image tags
replica settings
resource values
probe configuration
Deployment templates
```

It does not automatically undo external changes such as:

```text
database schema migrations
AWS infrastructure changes
data written by the new application version
```

Database changes must be backward-compatible or have their own recovery plan.

There are two different rollback owners:

```text
Manual Helm-managed release
  └── helm rollback

Argo CD / GitOps-managed release
  └── revert the bad Git commit and let Argo synchronize
```

If Terraform manages a `helm_release`, a manual Helm rollback is an
out-of-band change. Terraform may later try to restore the configuration in its
code. Likewise, if Argo CD manages the release, Argo may immediately
re-synchronize the Git version. Rollback must therefore use the tool that owns
the release in the production architecture.

### Choosing Terraform or Argo CD for application releases

The usual production separation is:

```text
Terraform
  └── AWS and cluster infrastructure
      VPC, EKS, IAM, node groups, add-ons, RDS, load balancers

Argo CD
  └── Kubernetes application delivery
      Helm releases, Deployments, Services, probes, policies
```

Terraform can manage a `helm_release`, and that is useful for a small setup or
for bootstrapping. However, it is usually not the best long-term application
release controller because Terraform runs are planned and executed explicitly,
while Argo CD continuously compares Git's desired state with the live cluster.

```text
Terraform helm_release
  └── apply runs Helm
      drift is corrected on a later Terraform run

Argo CD Application
  └── watches Git and the cluster continuously
      shows OutOfSync and can self-heal
```

For an Argo-managed application, the preferred rollback is an auditable Git
change:

```text
Bad application commit
        │
        ▼
Revert Git commit or change image tag to known-good tag
        │
        ▼
Argo CD detects desired-state change
        │
        ▼
Argo synchronizes the previous application version
```

Argo CD also has rollback commands, but automated sync and rollback need to be
planned together; Argo CD documents that rollback cannot be performed against
an application with automated sync enabled because automation would restore
the Git desired state. See [Argo CD automated
sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) and
[Argo CD rollback](https://argo-cd.readthedocs.io/en/release-2.13/user-guide/commands/argocd_app_rollback/).

The important rule is single ownership:

```text
Do not let both Terraform and Argo CD manage the same Helm release.
```

For the Synchat learning architecture, the target is:

```text
Terraform
  └── creates EKS and platform infrastructure

Argo CD
  └── deploys charts/synchat from Git

Git revert
  └── performs the normal application rollback
```

```text
No capacity or failed readiness
        │
        ▼
New Pod cannot become ready
        │
        ▼
Old Pod remains serving
        │
        ▼
Deployment rollout is incomplete, but availability is protected
```

Before a production rollout, verify that the cluster can temporarily hold the
surge Pods and that the application is backward-compatible during the overlap
between old and new versions. Database schema changes must be compatible with
both versions during this period.

### Deferred chart lifecycle topics

We are temporarily deferring chart dependency management, packaging/publishing,
and chart versioning so the learning path can focus on deployment behavior,
CI, and GitOps.

Argo CD does not replace these practices:

```text
Chart lifecycle
  ├── dependencies
  ├── packaging
  ├── publishing
  └── versioning

Argo CD
  └── consumes the chart from Git or a chart registry
```

We will return to these topics when the release process needs a published OCI
chart or a versioned chart registry workflow.

### GitHub Actions from first principles

GitHub Actions is an automation system attached to a GitHub repository. A
workflow is a YAML file under `.github/workflows/` that tells GitHub when to
run automation and what to do.

```text
GitHub event
  └── push, pull request, manual dispatch, schedule, or release
          │
          ▼
Workflow
  └── YAML automation definition
          │
          ▼
Job
  └── group of work executed on one runner
          │
          ▼
Steps
  ├── reusable Actions
  └── shell commands
```

The important terms are:

```text
Workflow
  └── complete automation file

Event / trigger
  └── what starts the workflow

Runner
  └── temporary VM or machine that executes a job

Job
  └── unit of work; jobs can run in parallel or depend on one another

Step
  └── one command or reusable action inside a job

Action
  └── reusable packaged automation, such as checking out Git code
```

The Synchat workflow currently has this shape:

```yaml
name: Validate Synchat Helm chart

on:
  pull_request:
  push:
    branches: [main]

jobs:
  helm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-helm@v4
      - run: helm lint ...
      - run: helm template ...
```

Read it as:

```text
When a pull request or main push happens:
  1. GitHub creates an Ubuntu runner
  2. checkout downloads the repository
  3. setup-helm installs Helm
  4. helm lint checks chart structure
  5. helm template renders the environments
```

`uses` and `run` are different:

```text
uses: actions/checkout@v4
  └── runs reusable action maintained for GitHub Actions

run: helm lint ...
  └── runs a shell command on the runner
```

The runner is temporary:

```text
Job starts
  └── fresh GitHub-hosted VM
        ├── repository checked out
        ├── tools installed
        ├── commands executed
        └── VM discarded after the job
```

The workflow's `permissions` block limits the GitHub token. The current job
only needs to read repository contents:

```yaml
permissions:
  contents: read
```

This is separate from AWS permissions. Later, when CI pushes images to ECR,
GitHub Actions will use GitHub OIDC to obtain short-lived AWS credentials. It
should not use a long-lived AWS access key stored in GitHub secrets.

The current CI job is deliberately only a validation gate:

```text
Chart invalid
  └── job fails; later jobs should not proceed

Chart valid
  └── future jobs may test code, build images, scan them, and publish them
```

The workflow does not deploy to Kubernetes. Deployment belongs to Argo CD after
the GitOps desired state has been updated.

### GitHub-hosted versus self-hosted runners

The Synchat workflow uses:

```yaml
runs-on: ubuntu-latest
```

This selects a GitHub-hosted runner:

```text
GitHub receives workflow event
        │
        ▼
GitHub provisions temporary Ubuntu VM
        │
        ▼
Workflow commands run on that VM
        │
        ▼
VM is discarded after the job
```

The machine is not the developer's laptop and is not an EC2 instance in the
user's AWS account. GitHub provides the operating system, runner agent, and a
standard set of preinstalled tools. Actions can install additional tools, such
as Helm.

```text
uses: actions/checkout@v4
  └── downloads the repository onto the runner

uses: azure/setup-helm@v4
  └── installs Helm on the runner

run: helm lint ...
  └── executes a shell command on the runner
```

GitHub-hosted runners are free for standard runners in public repositories. For
private repositories, the account receives a plan-dependent monthly allowance;
usage beyond that allowance is billed. Self-hosted runner execution is not
charged as GitHub-hosted runner minutes, but the machine itself still costs
money if it runs on AWS. See [GitHub Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage).

A self-hosted runner is a machine operated by the team:

```text
AWS EC2 / EKS runner machine
        │ runs
GitHub Actions runner agent
        │ receives jobs
GitHub Actions workflow
```

The workflow selects one with:

```yaml
runs-on: [self-hosted, linux, x64]
```

Terraform can provision the EC2 instance, security group, IAM role, and related
infrastructure for a self-hosted runner. It does not magically turn
`ubuntu-latest` into an AWS machine; the runner must be installed and
registered with GitHub separately. Self-hosted runners also require stronger
security controls because workflow code executes on a machine the team owns.

For the Synchat architecture, GitHub-hosted runners are the simpler default:

```text
GitHub-hosted runner
  ├── test code
  ├── validate Helm
  ├── build and scan images
  ├── push images to ECR using OIDC
  └── update GitOps repository

Argo CD inside/near the cluster
  └── reads Git and deploys Kubernetes
```

Because Argo CD owns deployment, GitHub Actions does not need direct network
access to the Kubernetes API. That removes one reason to operate a
self-hosted runner inside the AWS VPC.

### GitHub-hosted runner → OIDC → ECR → GitOps → Argo CD → EKS

This is the complete production delivery path:

```text
GitHub-hosted runner
        │
        ├── OIDC → AWS
        ├── push image → ECR
        └── update GitOps repository
                         │
                         ▼
                       Argo CD
                         │
                         ▼
                         EKS
```

#### 1. GitHub-hosted runner

GitHub starts a temporary machine for the workflow:

```text
GitHub repository event
        │
        ▼
Temporary Ubuntu runner
        │
        ├── checks out application code
        ├── runs tests
        ├── builds Docker images
        └── runs security checks
```

The runner is where the commands execute. It is not the Kubernetes cluster.

#### 2. OIDC gives the runner temporary AWS access

OIDC means OpenID Connect. GitHub issues a short-lived identity token for the
workflow. AWS verifies that token and exchanges it for temporary credentials.

```text
GitHub Actions workflow
        │ presents OIDC token
        ▼
AWS IAM trust policy
        │ verifies repository, branch, and workflow conditions
        ▼
Temporary AWS credentials
```

The workflow should not store a permanent AWS access key in GitHub Secrets:

```text
Preferred:
GitHub OIDC → IAM role → temporary credentials

Avoid:
AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY stored long-term in CI
```

The IAM role should allow only the actions required by the workflow, such as
logging in to ECR and pushing images to the Synchat repositories.

#### 3. The runner pushes images to ECR

ECR is Amazon Elastic Container Registry, a private AWS registry for container
images.

```text
Source code
        │
        ▼
Docker build
        │
        ▼
Synchat API image
        │
        ▼
ECR repository
```

The image should use an immutable tag:

```text
ECR image:
123456789012.dkr.ecr.us-east-1.amazonaws.com/synchat-api:a1b2c3d
```

The Git commit SHA `a1b2c3d` identifies the exact source used to build the
image.

#### 4. The runner updates the GitOps repository

The GitOps repository stores the desired deployment configuration:

```yaml
api:
  image:
    repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/synchat-api
    tag: a1b2c3d
```

The application source repository and GitOps repository may be separate:

```text
Application repository
  └── source code and Dockerfiles

GitOps repository
  └── Helm values and environment deployment configuration
```

The CI job can open a pull request or commit the new image tag, depending on
the team's release policy.

```text
New image published to ECR
        │
        ▼
GitOps values change from tag v1 to tag a1b2c3d
        │
        ▼
Git history records the desired release
```

#### 5. Argo CD watches Git

Argo CD runs in or has access to the Kubernetes cluster. It watches the GitOps
repository and compares Git with the live cluster:

```text
Git desired state
        │
        ├── matches cluster → Synced
        │
        └── differs          → OutOfSync
```

Argo CD renders the Helm chart using the selected values and applies the
resulting Kubernetes resources. GitHub Actions does not need to run `kubectl`
against the production cluster.

#### 6. Argo CD deploys to EKS

EKS is the managed Kubernetes cluster. Argo CD applies the desired resources:

```text
Argo CD
  └── applies Helm output to EKS
        ├── Deployment
        ├── Service
        ├── ConfigMap
        ├── HPA
        ├── PDB
        └── Gateway / HTTPRoute
```

Kubernetes then performs the rolling update:

```text
New ECR image tag
        │
        ▼
Argo CD sync
        │
        ▼
EKS Deployment
        │
        ▼
New Pods start and pass readiness
        │
        ▼
Traffic moves to the new version
```

The central principle is:

```text
CI creates and publishes the artifact.
Git records the desired release.
Argo CD deploys the desired release.
EKS runs the workloads.
```

### What can be learned with a local Kubernetes simulator

A local simulator can exercise some pipeline behavior, but it cannot reproduce
the full AWS production boundary.

```text
Capability                         Local simulator       Real AWS fidelity

GitHub Actions workflow            yes                   yes
Helm lint/template validation      yes                   yes
Build Docker images                yes                   yes
Argo CD Git reconciliation         yes, on local K8s     yes
ECR repository API                 partial               yes
ECR vulnerability scanning         not equivalent        yes
GitHub OIDC → AWS IAM              not full fidelity      yes
EKS control plane                  not equivalent        yes
AWS load balancer integration      not equivalent        yes
VPC routing and security groups    not equivalent        yes
```

There is also a network boundary:

```text
GitHub-hosted runner
  └── cannot reach localhost on the developer's laptop
```

Therefore a GitHub-hosted workflow can reliably run chart validation and build
steps, but it cannot push to a registry available only at a local endpoint. A
self-hosted runner on the same network could reach it, but that introduces the
runner-management and security concerns described above.

For this curriculum, the practical split is:

```text
Now, without AWS:
  ├── learn GitHub Actions workflow structure
  ├── run tests and Helm validation
  ├── understand immutable image tags
  ├── learn Argo CD desired-state reconciliation
  └── practice Git-based rollback

Requires real AWS for full fidelity:
  ├── GitHub OIDC trust with AWS IAM
  ├── push and pull from private ECR
  ├── ECR vulnerability scanning
  ├── EKS Pod Identity and add-ons
  ├── AWS load balancer behavior
  └── VPC/security-group enforcement
```

The local environment is therefore useful for the control-flow lessons, but
the production AWS integrations should be treated as separate platform steps,
not assumed to be equivalent because an API with the same name exists locally.

### Combined GitHub Actions and Argo CD learning path

We will learn CI and GitOps as one release pipeline rather than as unrelated
tools:

```text
GitHub Actions
  ├── tests code
  ├── renders and validates Helm
  ├── runs smoke/Helm tests
  ├── builds and scans images
  ├── publishes immutable images
  └── updates the GitOps image tag
          │
          ▼
Git desired state
          │
          ▼
Argo CD
  ├── detects the Git change
  ├── renders the chart
  ├── syncs Kubernetes
  ├── reports health and drift
  └── rolls back through a Git revert
```

The ownership boundary is:

```text
Terraform
  └── AWS and cluster infrastructure

GitHub Actions
  └── build, test, scan, publish, and propose release changes

Argo CD
  └── continuously reconcile Kubernetes to Git
```

Helm tests belong inside CI or as a post-sync validation step; they are not a
separate deployment owner. Chart packaging and versioning remain deferred
until a chart registry workflow is actually needed.

### GitHub Actions: first CI stage

The repository now has a workflow at `.github/workflows/helm-validate.yml`.
Its first job validates the Synchat chart without deploying anything:

```text
Pull request or push to main
          │
          ▼
GitHub Actions
  ├── check out the repository
  ├── install Helm
  ├── run helm lint
  └── render dev, stage, and prod values
```

The workflow supplies the Git commit SHA as the image tag while rendering:

```text
GitHub commit SHA
        │
        ▼
web.image.tag
api.image.tag
crawler.image.tag
        │
        ▼
Helm renders the exact release inputs
```

This job does not build images, push to ECR, deploy Kubernetes, or contact
Argo CD. It is the first gate in the pipeline:

```text
Invalid chart
  └── CI fails; no release proceeds

Valid chart
  └── later CI jobs may build and publish images

### GitHub Container Registry (GHCR) versus Amazon ECR

GHCR is GitHub's registry for Docker and OCI container images. For learning,
we can publish Synchat images there without creating an AWS account:

```text
GitHub Actions runner
        │
        │ GITHUB_TOKEN with packages: write
        ▼
ghcr.io/<github-user>/synchat-api:<commit-sha>
        │
        ▼
Kubernetes pulls the immutable image tag
```

Public GitHub packages are free. GitHub currently also states that Container
Registry image storage and bandwidth are free, but this policy can change.
Private GitHub Packages have plan quotas and may be billed after the included
quota is exceeded. Keep images small and remove old tags.

GHCR and ECR teach the same basic image lifecycle:

```text
Build image → tag image → push image → deploy that exact tag
```

They are not identical:

```text
GHCR                         Amazon ECR
────                         ──────────
Owned by GitHub              AWS-native registry
GitHub permissions           IAM permissions
GITHUB_TOKEN                 GitHub OIDC → IAM role
Good for learning cheaply   Production choice for AWS workloads
```

Using GHCR lets us learn image building, immutable tags, and Argo CD without
AWS. Moving from GHCR to ECR later changes the registry URL and authentication
step; the Kubernetes Deployment still refers to an image and tag in the same
way. A private GHCR image also requires Kubernetes pull credentials, while a
public image can be pulled anonymously.
```
