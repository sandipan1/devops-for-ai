resource "helm_release" "envoy_gateway" {
  name             = "eg"
  namespace        = "envoy-gateway-system"
  create_namespace = true

  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = "v1.6.7"

  wait    = true
  timeout = 600
}

resource "helm_release" "platform_gateway" {
  name             = "platform-gateway"
  namespace        = "platform-system"
  create_namespace = true

  chart = abspath("${path.module}/../charts/platform-gateway")

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.envoy_gateway
  ]
}

resource "helm_release" "synchat" {
  name             = "synchat"
  namespace        = "synchat-dev"
  create_namespace = true

  chart = abspath("${path.module}/../charts/synchat")

  values = [
    file("${path.module}/../synchat-deployment/values-dev.yaml")
  ]

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.platform_gateway
  ]
}
