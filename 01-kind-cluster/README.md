# 01 - Kind Cluster

Create a local Kubernetes cluster using [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker) for testing all subsequent concepts.

## Prerequisites

- Docker running
- `kind` CLI installed ([install guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- `kubectl` installed

## Step-by-Step

```bash
bash scripts/create-cluster.sh
```

## How to Verify

```bash
kubectl cluster-info --context kind-claude-demo
kubectl get nodes
```

## Expected Output

```
Kubernetes control plane is running at https://127.0.0.1:XXXXX

NAME                        STATUS   ROLES           AGE   VERSION
claude-demo-control-plane   Ready    control-plane   30s   v1.31.0
```

## Cleanup

```bash
kind delete cluster --name claude-demo
```
