#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'USAGE'
Cleanup k6 Job/ConfigMap and optionally the namespace (macOS/Linux)

Usage:
  bash ./scripts/cleanup.sh [--namespace loadtest] [--job-name k6-loadtest] [--delete-namespace]

Options:
  --namespace NAME       Kubernetes namespace (default: loadtest)
  --job-name NAME        Job name (default: k6-loadtest)
  --delete-namespace     Also delete the namespace
USAGE
}

namespace="loadtest"
job_name="k6-loadtest"
delete_ns="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage; exit 0;
      ;;
    --namespace)
      namespace=${2:-}; shift 2;
      ;;
    --job-name)
      job_name=${2:-}; shift 2;
      ;;
    --delete-namespace)
      delete_ns="true"; shift 1;
      ;;
    *)
      echo "Unknown option: $1" >&2; print_usage; exit 1;
      ;;
  esac
done

echo "Deleting Job $job_name in '$namespace'..."
kubectl -n "$namespace" delete job "$job_name" --ignore-not-found

echo "Deleting ConfigMap k6-test-files in '$namespace'..."
kubectl -n "$namespace" delete configmap k6-test-files --ignore-not-found

if [[ "$delete_ns" == "true" ]]; then
  echo "Deleting namespace '$namespace'..."
  kubectl delete namespace "$namespace" --ignore-not-found
fi


