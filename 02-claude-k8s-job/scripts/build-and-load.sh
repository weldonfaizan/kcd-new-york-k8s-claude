#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-claude-demo}"
IMAGE_NAME="${IMAGE_NAME:-claude-code}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "$CONTEXT_DIR"

echo "Loading image into Kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "${CLUSTER_NAME}"

echo "Done! Image ${IMAGE_NAME}:${IMAGE_TAG} is available in the cluster."
