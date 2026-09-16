#!/usr/bin/env bash

set -euo pipefail

cluster_name="synchat-eks"
context_name="synchat-eks-admin"
api_server="https://localhost:16443"
kube_dir="${HOME}/.kube"
admin_config="${kube_dir}/${cluster_name}-admin.yaml"
main_config="${kube_dir}/config"

container_id="$({ docker ps --format '{{.ID}} {{.Names}}' | awk '$2 == "ministack-eks-us-east-1-synchat-eks" { print $1; exit }'; })"

if [[ -z "${container_id}" ]]; then
  echo "MiniStack EKS container is not running: ministack-eks-us-east-1-synchat-eks" >&2
  exit 1
fi

mkdir -p "${kube_dir}"

# Copy the k3s admin config without printing its embedded client credentials.
docker cp "${container_id}:/etc/rancher/k3s/k3s.yaml" "${admin_config}" >/dev/null
chmod 600 "${admin_config}"

kubectl --kubeconfig="${admin_config}" config set-cluster default \
  --server="${api_server}" >/dev/null
kubectl --kubeconfig="${admin_config}" config rename-context default "${context_name}" >/dev/null

# Merge the durable admin context into the normal kubeconfig.
merged_config="$(mktemp)"
if [[ -f "${main_config}" ]]; then
  KUBECONFIG="${main_config}:${admin_config}" kubectl config view \
    --flatten >"${merged_config}"
else
  cp "${admin_config}" "${merged_config}"
fi

chmod 600 "${merged_config}"
mv "${merged_config}" "${main_config}"
kubectl config use-context "${context_name}" >/dev/null

echo "Configured kubectl context: ${context_name}"
echo "Kubeconfig: ${main_config}"
