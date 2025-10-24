#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'USAGE'
Run k6 locally via Docker (macOS/Linux)

Usage:
  bash ./scripts/run-local.sh [--base-url URL] [--vus N] [--duration 30s] \
      [--stages-json JSON] [--sleep SECS] [--endpoints-file PATH] [--p95 MS]

Options:
  --base-url URL        Base URL for endpoints (BASE_URL)
  --vus N               Number of virtual users (VUS, default: 10)
  --duration 30s        Test duration (DURATION, default: 30s)
  --stages-json JSON    k6 stages JSON string (STAGES_JSON). If set, overrides VUS/DURATION
  --sleep SECS          Sleep seconds between iterations (SLEEP, default: 1)
  --endpoints-file PATH Path to endpoints.json (default: ./config/endpoints.json)
  --p95 MS              P95 threshold in ms (P95, default: 800)
USAGE
}

base_url=""
vus="10"
duration="30s"
stages_json=""
sleep_secs="1"
endpoints_file=""
p95="800"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage; exit 0;
      ;;
    --base-url)
      base_url=${2:-}; shift 2;
      ;;
    --vus)
      vus=${2:-}; shift 2;
      ;;
    --duration)
      duration=${2:-}; shift 2;
      ;;
    --stages-json)
      stages_json=${2:-}; shift 2;
      ;;
    --sleep)
      sleep_secs=${2:-}; shift 2;
      ;;
    --endpoints-file)
      endpoints_file=${2:-}; shift 2;
      ;;
    --p95)
      p95=${2:-}; shift 2;
      ;;
    *)
      echo "Unknown option: $1" >&2; print_usage; exit 1;
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
k6_file="$repo_root/k6/test.js"
cfg_file_default="$repo_root/config/endpoints.json"

if [[ -z "$endpoints_file" ]]; then
  cfg_file="$cfg_file_default"
else
  cfg_file="$endpoints_file"
fi

if [[ ! -f "$k6_file" ]]; then
  echo "k6 script not found at $k6_file" >&2; exit 1;
fi
if [[ ! -f "$cfg_file" ]]; then
  echo "Endpoints config not found at $cfg_file" >&2; exit 1;
fi

env_args=()
if [[ -n "$base_url" ]]; then env_args+=( -e "BASE_URL=$base_url" ); fi
env_args+=( -e "VUS=$vus" )
env_args+=( -e "DURATION=$duration" )
env_args+=( -e "SLEEP=$sleep_secs" )
env_args+=( -e "P95=$p95" )
if [[ -n "$stages_json" ]]; then env_args+=( -e "STAGES_JSON=$stages_json" ); fi
env_args+=( -e "ENDPOINTS_FILE=/config/endpoints.json" )

docker run --rm \
  "${env_args[@]}" \
  -v "$k6_file:/scripts/test.js:ro" \
  -v "$cfg_file:/config/endpoints.json:ro" \
  grafana/k6:latest run /scripts/test.js


