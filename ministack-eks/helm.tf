provider "helm" {
  kubernetes = {
    config_path = "/tmp/synchat-eks-kubeconfig.yaml"
  }
}