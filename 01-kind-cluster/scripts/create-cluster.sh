#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-claude-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../../.env"

# Check prerequisites
for cmd in kind kubectl docker; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd is not installed or not in PATH"
    exit 1
  fi
done

# Check if Docker is running
if ! docker info &> /dev/null; then
  echo "Error: Docker is not running"
  exit 1
fi

# Check .env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at $ENV_FILE"
  echo "Copy .env.example to .env and add your real keys"
  exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Validate required vars
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Error: ANTHROPIC_API_KEY not set in .env"
  exit 1
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "Error: GH_TOKEN not set in .env"
  exit 1
fi

# Create cluster if it doesn't exist
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  echo "Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --wait 60s
fi

CTX="kind-${CLUSTER_NAME}"

# Create namespaces for each concept
echo "Setting up namespaces..."
for ns in 02-claude-k8s-job 03-sidecar-proxy 04-code-reviewer 05-developer-agent 06-kro-agent 07-sandbox; do
  kubectl create namespace "$ns" --context "$CTX" 2>/dev/null || true
done

# Create/recreate secrets in all namespaces
echo "Setting up secrets..."

for ns in 02-claude-k8s-job 03-sidecar-proxy 04-code-reviewer 05-developer-agent 06-kro-agent 07-sandbox; do
  kubectl delete secret agent-credentials -n "$ns" --context "$CTX" 2>/dev/null || true
  kubectl create secret generic agent-credentials \
    --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
    --from-literal=GH_TOKEN="$GH_TOKEN" \
    -n "$ns" --context "$CTX"
done

echo ""
echo "Cluster '${CLUSTER_NAME}' is ready!"
echo "Context: $CTX"
echo "Namespaces: 02-claude-k8s-job, 03-sidecar-proxy, 04-code-reviewer, 05-developer-agent, 06-kro-agent, 07-sandbox"
echo "Secrets: created in all namespaces"
echo ""
echo "Verify with: kubectl get nodes --context $CTX"
echo "Re-run this script anytime to refresh secrets from .env"
