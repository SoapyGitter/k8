#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'USAGE'
Deploy k6 job and ConfigMap to Kubernetes (macOS/Linux)

Usage:
  bash ./scripts/deploy.sh [--namespace loadtest] [--job-name k6-loadtest]

Options:
  --namespace NAME   Kubernetes namespace (default: loadtest)
  --job-name NAME    Job name label to display pods (default: k6-loadtest)
USAGE
}

namespace="loadtest"
job_name="k6-loadtest"

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
    *)
      echo "Unknown option: $1" >&2; print_usage; exit 1;
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
k6_dir="$script_dir/../k6"
cfg_dir="$script_dir/../config"
k8s_dir="$script_dir/../k8s"

echo "Ensuring namespace '$namespace' exists..."
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating/updating ConfigMap 'k6-test-files' from k6/test.js and config/endpoints.json..."
kubectl -n "$namespace" create configmap k6-test-files \
  --from-file="$k6_dir/test.js" \
  --from-file="$cfg_dir/endpoints.json" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applying Job manifest..."
kubectl -n "$namespace" apply -f "$k8s_dir/job.yaml"

echo "Job applied. Pods:"
kubectl -n "$namespace" get pods -l job-name="$job_name"

echo "To follow logs: kubectl -n $namespace logs -f job/$job_name"


