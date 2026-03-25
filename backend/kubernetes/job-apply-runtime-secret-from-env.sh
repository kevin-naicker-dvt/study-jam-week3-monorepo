#!/usr/bin/env bash
# Runnable "job": create/update Kubernetes Secret studyjam-k8s-runtime from a dotenv file
# (same keys as backend deployment: DB_PASSWORD, JWT_SECRET).
#
# Usage (from repo root or any cwd):
#   ./backend/kubernetes/job-apply-runtime-secret-from-env.sh
#   ./backend/kubernetes/job-apply-runtime-secret-from-env.sh /path/to/.env
#
# Default env file: backend/kubernetes/env/runtime-secrets.env
# Setup: cp backend/kubernetes/env/runtime-secrets.env.example backend/kubernetes/env/runtime-secrets.env
#
# Why not a Kubernetes Job YAML? Putting secrets in a Job spec exposes them in the API/etcd;
# this script sends values only through kubectl's secret create pipe (same as manual kubectl).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$ROOT/env/runtime-secrets.env}"
NS="studyjam-k8s"
SECRET="studyjam-k8s-runtime"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  echo "Copy the example and edit: cp \"$ROOT/env/runtime-secrets.env.example\" \"$ROOT/env/runtime-secrets.env\"" >&2
  exit 1
fi

require_var() {
  local key="$1"
  if ! grep -qE "^[[:space:]]*${key}=" "$ENV_FILE"; then
    echo "Missing key ${key} in ${ENV_FILE}" >&2
    exit 1
  fi
}

require_var DB_PASSWORD
require_var JWT_SECRET

if grep -E '^[[:space:]]*(DB_PASSWORD|JWT_SECRET)=[[:space:]]*REPLACE_WITH' "$ENV_FILE"; then
  echo "Replace placeholder values (REPLACE_WITH_…) in ${ENV_FILE} before applying." >&2
  exit 1
fi

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "$SECRET" \
  --namespace="$NS" \
  --from-env-file="$ENV_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret ${SECRET} applied in namespace ${NS} (metadata only: kubectl get secret ${SECRET} -n ${NS})"
