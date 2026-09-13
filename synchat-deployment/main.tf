terraform {
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }
  }
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to the kubeconfig used by the Helm provider."
  default     = "~/.kube/config"
}

variable "kube_context" {
  type        = string
  description = "The kubeconfig context Terraform must deploy to."
  default     = "minikube"
}

variable "app_namespace" {
  type        = string
  description = "Namespace for the Synchat application release."
  default     = "synchat-dev"
}
variable "environment" {
  type  = string 
  description  = "Deployment environment"
  default = "dev"

  validation { 
    condition  = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev,stage, or prod"
  }
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

resource "helm_release" "platform_gateway" {
  name             = "platform-gateway"
  namespace        = "platform-system"
  create_namespace = true
  chart            = abspath("${path.module}/../charts/platform-gateway")

  wait    = true
  timeout = 600
}

resource "helm_release" "synchat" {
  name             = "synchat"
  namespace        = var.app_namespace
  create_namespace = true
  chart            = abspath("${path.module}/../charts/synchat")

  wait    = true
  timeout = 600
  values = [
    file("${path.module}/values-${var.environment}.yaml")
  ]
  depends_on = [helm_release.platform_gateway]
}

output "application_release" {
  value = helm_release.synchat.name
}

output "application_namespace" {
  value = helm_release.synchat.namespace
}
