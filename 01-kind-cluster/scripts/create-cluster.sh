#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-claude-demo}"

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

# Delete existing cluster if it exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Deleting..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

# Create cluster
echo "Creating Kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}" --wait 60s

# Create namespace for demos
kubectl create namespace claude-demo --context "kind-${CLUSTER_NAME}" 2>/dev/null || true

echo ""
echo "Cluster '${CLUSTER_NAME}' is ready!"
echo "Context: kind-${CLUSTER_NAME}"
echo ""
echo "Verify with: kubectl get nodes --context kind-${CLUSTER_NAME}"
