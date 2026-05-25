#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-claude-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../../.env"

# Auth mode: "bedrock" (default) uses aws-vault EC2 metadata, "api-key" uses ANTHROPIC_API_KEY
AUTH_MODE="${AUTH_MODE:-bedrock}"
AWS_VAULT_PROFILE="${AWS_VAULT_PROFILE:-bedrock-claude}"

# Check prerequisites
REQUIRED_CMDS=(kind kubectl docker)
if [ "$AUTH_MODE" = "bedrock" ]; then
  REQUIRED_CMDS+=(aws-vault socat)
fi
for cmd in "${REQUIRED_CMDS[@]}"; do
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

# Validate required vars based on auth mode
if [ "$AUTH_MODE" = "api-key" ]; then
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Error: ANTHROPIC_API_KEY not set in .env"
    exit 1
  fi
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "Error: GH_TOKEN not set in .env"
  exit 1
fi

# --- Bedrock auth: start aws-vault EC2 metadata server ---
if [ "$AUTH_MODE" = "bedrock" ]; then
  echo "Starting aws-vault EC2 metadata server (profile: ${AWS_VAULT_PROFILE})..."

  # Kill any existing aws-vault ec2 metadata server
  sudo pkill -f "aws-vault.*ec2" 2>/dev/null || true
  sleep 1

  # Start metadata server in background
  aws-vault exec "${AWS_VAULT_PROFILE}" --ec2-server -- sleep infinity &
  AWS_VAULT_PID=$!

  # Wait for metadata server to be ready
  for i in {1..10}; do
    if curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/iam/security-credentials/ > /dev/null 2>&1; then
      echo "  Metadata server ready."
      break
    fi
    if [ "$i" -eq 10 ]; then
      echo "Error: aws-vault metadata server failed to start"
      kill "$AWS_VAULT_PID" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done

  # Start host-side socat bridge (metadata server only binds to 169.254.169.254)
  pkill -f "socat TCP-LISTEN:9999" 2>/dev/null || true
  sleep 1
  socat TCP-LISTEN:9999,fork,reuseaddr TCP:169.254.169.254:80 &
  SOCAT_HOST_PID=$!
  echo "  Host socat bridge ready (pid: ${SOCAT_HOST_PID})."
fi

# Create cluster if it doesn't exist
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  echo "Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --wait 60s
fi

CTX="kind-${CLUSTER_NAME}"

# --- Bedrock auth: set up metadata routing inside Kind node ---
if [ "$AUTH_MODE" = "bedrock" ]; then
  echo "Setting up EC2 metadata routing in Kind node..."
  HOST_IP=$(docker exec "${CLUSTER_NAME}-control-plane" bash -c 'getent ahosts host.docker.internal' | grep -m1 'STREAM' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "192.168.65.254")

  docker exec "${CLUSTER_NAME}-control-plane" bash -c "
    apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq socat > /dev/null 2>&1
    pkill socat 2>/dev/null || true
    ip addr add 169.254.169.254/32 dev lo 2>/dev/null || true
    nohup socat TCP-LISTEN:80,bind=169.254.169.254,fork,reuseaddr TCP:${HOST_IP}:9999 > /dev/null 2>&1 &
  "

  # Verify end-to-end from inside the node
  if docker exec "${CLUSTER_NAME}-control-plane" curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/iam/security-credentials/ | grep -q "local-credentials"; then
    echo "  EC2 metadata routing verified."
  else
    echo "Warning: EC2 metadata not reachable from Kind node — pods may not get Bedrock credentials"
  fi
fi

# Create namespaces for each concept
echo "Setting up namespaces..."
for ns in 02-claude-k8s-job 03-sidecar-proxy 04-code-reviewer 05-developer-agent 06-kro-agent 07-sandbox; do
  kubectl create namespace "$ns" --context "$CTX" 2>/dev/null || true
done

# Create/recreate secrets in all namespaces
echo "Setting up secrets..."

for ns in 02-claude-k8s-job 03-sidecar-proxy 04-code-reviewer 05-developer-agent 06-kro-agent 07-sandbox; do
  kubectl delete secret agent-credentials -n "$ns" --context "$CTX" 2>/dev/null || true

  if [ "$AUTH_MODE" = "bedrock" ]; then
    kubectl create secret generic agent-credentials \
      --from-literal=GH_TOKEN="$GH_TOKEN" \
      -n "$ns" --context "$CTX"
  else
    kubectl create secret generic agent-credentials \
      --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
      --from-literal=GH_TOKEN="$GH_TOKEN" \
      -n "$ns" --context "$CTX"
  fi
done

echo ""
echo "Cluster '${CLUSTER_NAME}' is ready!"
echo "Context: $CTX"
echo "Auth mode: $AUTH_MODE"
if [ "$AUTH_MODE" = "bedrock" ]; then
  echo "  Pods get AWS credentials via EC2 metadata (169.254.169.254)"
  echo "  Set CLAUDE_CODE_USE_BEDROCK=1 and AWS_REGION=us-west-2 on pods"
  echo "  Metadata server dies when this terminal closes — re-run script to restart"
fi
echo "Namespaces: 02-claude-k8s-job, 03-sidecar-proxy, 04-code-reviewer, 05-developer-agent, 06-kro-agent, 07-sandbox"
echo "Secrets: created in all namespaces"
echo ""
echo "Verify with: kubectl get nodes --context $CTX"
echo "Re-run this script anytime to refresh secrets from .env"
