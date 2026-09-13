# Helm-managed Gateway setup

This directory contains the Helm charts used to manage the Kubernetes Gateway
layer and, eventually, the Synchat application.

The ownership is split into three Helm releases:

```text
Helm release: eg
└── Envoy Gateway controller and Gateway API CRDs

Helm release: platform-gateway
└── GatewayClass

Helm release: synchat
├── Deployments
├── Services
├── ConfigMaps
├── Gateway
└── HTTPRoutes
```

`GatewayClass` is cluster-scoped, so it belongs to the platform layer. The
`Gateway` and `HTTPRoute` resources are application-facing resources and will
belong to the `synchat` chart.

## Custom resources, CRDs, and controllers

Kubernetes already understands resource types such as `Deployment`, `Service`,
and `ConfigMap`. A **CustomResourceDefinition (CRD)** extends Kubernetes with
another type, such as `Gateway`. Once its CRD is installed, you can create
objects of that type, called **custom resources**.

A database analogy helps distinguish the pieces:

| Kubernetes concept | Database analogy |
|---|---|
| CRD | Table definition: which fields are allowed |
| Custom resource | A row containing actual values |
| Controller | Software that reads those values and takes action |

For example, your platform chart renders:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: app-gatewayclass
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

This creates one custom resource named `app-gatewayclass`. It works because
the `GatewayClass` CRD was installed first. The CRD lets Kubernetes store and
validate the object; the controller implements its requested behavior.

See the [Kubernetes custom resources documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/).

### Gateway API resources

These types are defined by the Kubernetes Gateway API project and can be
implemented by different controllers. They describe how traffic enters and
reaches an application.

| Resource | Purpose in this setup |
|---|---|
| `GatewayClass` | Selects Envoy Gateway as the controller. Many Gateways can reference this class through `gatewayClassName`. |
| `Gateway` | Requests an entry point with listeners, such as HTTP on port 80. |
| `HTTPRoute` | Defines which hostname and path go to which Service. |

Together, these objects can express: use Envoy, listen on port 80, and send
requests for `synchat.internal` to the web Service.

The `GatewayClass` object is itself a blueprint for Gateways. That is a
different relationship from a CRD defining a resource type: the `GatewayClass`
CRD defines the type, `app-gatewayclass` is an object of that type, and
individual Gateway objects reference `app-gatewayclass`.

See the [Gateway API concepts](https://gateway.envoyproxy.io/docs/concepts/gateway-api/).

### Envoy-specific resources

Envoy Gateway also provides custom resource types in its own API group,
`gateway.envoyproxy.io`, for additional configuration.

| Resource | Purpose |
|---|---|
| `EnvoyProxy` | Customizes the managed proxy infrastructure, such as resource settings. |
| `SecurityPolicy` | Configures security features such as authentication. |
| `BackendTrafficPolicy` | Configures traffic behavior such as retries or rate limiting. |

The Envoy Helm installation includes these definitions alongside the Gateway
API definitions. Installing a CRD makes a type available; it does not require
you to create an instance of every type. We can start with `GatewayClass`,
`Gateway`, and `HTTPRoute`, then add policies as the application needs them.

See the [Envoy Gateway installation guide](https://gateway.envoyproxy.io/docs/install/install-helm/).

### From configuration to traffic

**Envoy Gateway is the controller; Envoy Proxy handles the requests.** The
controller reads the custom resources and creates or configures the proxy
infrastructure to implement them.

```text
Your YAML objects
GatewayClass + Gateway + HTTPRoute + optional policies
                         |
                         | read by
                         v
              Envoy Gateway controller
                         |
                         | creates/configures
                         v
Browser ------------> Envoy Proxy ------------> Application Pods
                       handles traffic
```

The route selects a Kubernetes Service as its backend; the diagram simplifies
the traffic path to show the proxy forwarding to the application pods.

After installing the charts, inspect the definition and an actual object:

```bash
# The definition of the GatewayClass type
kubectl get crd gatewayclasses.gateway.networking.k8s.io

# The object created by the platform Helm chart
kubectl get gatewayclass app-gatewayclass
```

The earlier CRD conflict happened while installing the definitions, before the
controller could be successfully installed. Deleting the Envoy namespace did
not remove those definitions because CRDs are cluster-scoped.

## Chart layout

```text
charts/
├── platform-gateway/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       └── gateclass.yaml
└── synchat/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

Every Kubernetes manifest that Helm should render must be inside a chart's
`templates/` directory. A YAML file placed directly beside `Chart.yaml` is
not rendered as a template.

## Prerequisites

Run the following commands from the repository's `terraform-practice` directory:

```bash
cd /Users/sandipan/projects/backend_engineering/terraform-practice
```

Confirm that Kubernetes is available:

```bash
kubectl config current-context
kubectl get nodes
helm version
```

The current learning cluster is Minikube. The same Helm workflow can later be
used against a MiniStack or cloud Kubernetes cluster.

## Optional: reset the old Gateway practice setup

Use this only to simulate a fresh Gateway installation on the existing
learning cluster. The commands remove Gateway API CRDs, so do not run them on
a shared cluster where another Gateway controller is using them.

Skip this entire reset section on a new cluster. Deleting a CRD deletes every
instance of that resource type across the cluster. Before cleanup, inspect all
three groups, including policies and experimental resources:

```bash
kubectl config current-context
helm list --all-namespaces
kubectl get crd -o json | jq -r '
  .items[] |
  select(.spec.group == "gateway.networking.k8s.io" or
         .spec.group == "gateway.networking.x-k8s.io" or
         .spec.group == "gateway.envoyproxy.io") |
  .metadata.name' |
while IFS= read -r crd; do
  kubectl get "$crd" --all-namespaces -o name || break
done
```

This inventory uses `jq`. If it reports resources, inspect their owners before
deleting their definitions. The cleanup below was verified against an unused
Gateway installation in the Minikube learning cluster.

First remove old Gateway API objects if they exist:

```bash
kubectl delete gatewayclass app-gatewayclass --ignore-not-found
kubectl delete gateway app-gateway --namespace default --ignore-not-found
kubectl delete httproute api-httproute web-httproute \
  --namespace default \
  --ignore-not-found
```

If the old Envoy namespace still exists, remove it:

```bash
helm uninstall eg \
  --namespace envoy-gateway-system \
  --ignore-not-found

kubectl delete namespace envoy-gateway-system --ignore-not-found
```

The old manually installed Envoy controller also left cluster permissions
behind. Inspect these exact objects and confirm their bindings refer only to
service accounts in `envoy-gateway-system`:

```bash
kubectl get clusterrolebinding \
  eg-gateway-helm-envoy-gateway-rolebinding \
  eg-gateway-helm-certgen:envoy-gateway-system -o yaml
```

After removing the old controller, remove these leftovers if present:

```bash
kubectl delete clusterrolebinding \
  eg-gateway-helm-envoy-gateway-rolebinding \
  eg-gateway-helm-certgen:envoy-gateway-system --ignore-not-found
kubectl delete clusterrole \
  eg-gateway-helm-envoy-gateway-role \
  eg-gateway-helm-certgen:envoy-gateway-system --ignore-not-found
```

These names are specific to this practice installation. Do not delete unrelated
cluster roles. An error about missing `meta.helm.sh/release-name` on an existing
ClusterRole is a Helm ownership error, distinct from the CRD field conflict.

Envoy Gateway's Helm release does not automatically remove CRDs. To make the
existing cluster equivalent to a fresh cluster, remove the old Gateway API,
experimental Gateway API, and Envoy Gateway CRDs:

```bash
kubectl delete crd \
  backends.gateway.envoyproxy.io \
  backendtlspolicies.gateway.networking.k8s.io \
  backendtrafficpolicies.gateway.envoyproxy.io \
  clienttrafficpolicies.gateway.envoyproxy.io \
  envoyextensionpolicies.gateway.envoyproxy.io \
  envoypatchpolicies.gateway.envoyproxy.io \
  envoyproxies.gateway.envoyproxy.io \
  gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  grpcroutes.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  httproutefilters.gateway.envoyproxy.io \
  listenersets.gateway.networking.k8s.io \
  referencegrants.gateway.networking.k8s.io \
  securitypolicies.gateway.envoyproxy.io \
  tcproutes.gateway.networking.k8s.io \
  tlsroutes.gateway.networking.k8s.io \
  udproutes.gateway.networking.k8s.io \
  xbackends.gateway.networking.x-k8s.io \
  xbackendtrafficpolicies.gateway.networking.x-k8s.io \
  xlistenersets.gateway.networking.x-k8s.io \
  xmeshes.gateway.networking.x-k8s.io \
  --ignore-not-found
```

This reset does not remove the Synchat application release. To inspect it:

```bash
helm list --all-namespaces
```

### Why the earlier installation conflicted

The failed installation left a mixed set of definitions: most Gateway API CRDs
reported bundle `v1.6.1`, while `xbackendtrafficpolicies` and `xlistenersets`
still reported `v1.3.0`. Checking only the `gateways` CRD did not reveal this.

The error `conflicts with "kubectl"` referred to server-side apply field
ownership: the new installation attempted to change schema and annotation
fields previously managed by `kubectl`. It was not a missing namespace or an
old kubectl client. Removing a namespace cannot remove cluster-scoped CRDs.

For this fresh-install exercise, remove the unused old definitions using the
complete list above, then run Step 1. In an existing shared environment, use
the official CRD upgrade procedure and check compatibility instead.

`--set crds.enabled=false` is valid when all required compatible CRDs are
already installed and managed separately. It skips their installation; it does
not repair old or missing definitions. `helm template ... | kubectl apply`
uses Helm to render YAML but does not create a Helm release for those CRDs.

Do not use `--validate=false` to work around missing `apiVersion` or `kind`;
inspect the rendered YAML first. `--server-side` belongs to `kubectl apply`,
not `kubectl delete`. `--force-conflicts` deliberately transfers field
ownership and requires an intentional upgrade decision.

## Step 1: install Envoy Gateway with Helm

Envoy Gateway is the controller that watches `GatewayClass`, `Gateway`, and
`HTTPRoute` resources. Installing a `GatewayClass` alone does not install a
controller.

Install Envoy Gateway and its CRDs:

```bash
helm install eg \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.9.1 \
  --namespace envoy-gateway-system \
  --create-namespace
```

Wait until the controller is ready:

```bash
kubectl wait \
  --timeout=5m \
  --namespace envoy-gateway-system \
  deployment/envoy-gateway \
  --for=condition=Available
```

Verify the controller:

```bash
kubectl get pods --namespace envoy-gateway-system
helm list --namespace envoy-gateway-system
```

Proceed only after the installation succeeds and the controller is available.
CRDs installed from the chart's `crds/` directory are treated specially by
Helm: normal release uninstall does not delete them, and normal upgrades do
not automatically upgrade them. Follow the official CRD upgrade instructions
when changing Envoy Gateway versions.

The chart and installation details are documented in the [official Envoy
Gateway Helm guide](https://gateway.envoyproxy.io/docs/install/install-helm/).

Do not apply Envoy's `quickstart.yaml` for this exercise. That would create
Gateway resources outside our Helm releases.

## Step 2: preview the platform chart

The platform chart creates the cluster-scoped `app-gatewayclass`, as configured
in `platform-gateway/values.yaml`.

Check the chart:

```bash
helm lint charts/platform-gateway
```

Render it locally without changing the cluster:

```bash
helm template platform-gateway charts/platform-gateway \
  --namespace platform-system
```

The output should contain a resource similar to:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: app-gatewayclass
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

`helm template` only prints the manifests. It does not install them.

## Step 3: install the platform chart

```bash
helm install platform-gateway charts/platform-gateway \
  --namespace platform-system \
  --create-namespace
```

Verify the `GatewayClass`:

```bash
kubectl get gatewayclass
kubectl describe gatewayclass app-gatewayclass
helm list --namespace platform-system
```

Expected result:

```text
NAME                  CONTROLLER                                      ACCEPTED
app-gatewayclass      gateway.envoyproxy.io/gatewayclass-controller   True
```

If `ACCEPTED` is `False`, inspect the Envoy Gateway controller first:

```bash
kubectl get pods --namespace envoy-gateway-system
kubectl logs deployment/envoy-gateway \
  --namespace envoy-gateway-system
```

The `controllerName` in `platform-gateway/values.yaml` must match the
controller installed in the cluster. Envoy Gateway is one possible Gateway
controller; another controller would use a different controller name.

## Step 4: deploy the complete application chart

The `synchat` chart owns the three application workloads in one namespace:

```text
synchat Helm release, namespace synchat-dev
├── web Deployment
├── web Service
├── web ConfigMap
├── api Deployment
├── api Service
├── api ConfigMap
├── crawler Deployment
├── crawler Service
├── crawler ConfigMap
├── Gateway
└── HTTPRoutes
```

All three workloads run in `synchat-dev`. The API calls the crawler through
the internal `crawler-service` Service. The browser reaches the API through
the API hostname, so the chart creates two routes on the same Gateway:

```text
synchat.internal     -> web-service:80
synchatapi.internal  -> api-service:80
api-service          -> crawler-service:80   (inside the cluster)
```

The application chart references the platform class through a `Gateway`:

```yaml
spec:
  gatewayClassName: app-gatewayclass
```

The application chart should not create another `GatewayClass`. It creates a
namespaced `Gateway` and attaches the web and API `HTTPRoute` resources to it.

Before installing or upgrading the application chart, always preview it:

```bash
helm lint charts/synchat

helm template synchat charts/synchat \
  --namespace synchat-dev
```

Then install or update it through Helm:

```bash
helm upgrade --install synchat charts/synchat \
  --namespace synchat-dev \
  --create-namespace
```

After this migration, use Helm for normal application changes. Use `kubectl`
for inspection and troubleshooting, not as the normal deployment mechanism.
