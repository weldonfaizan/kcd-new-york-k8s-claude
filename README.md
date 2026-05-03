# Platform Engineering for AI Agents: Secure Claude Code on Kubernetes with KRO

Reference implementation for the [KCD New York](https://community.cncf.io/kcd-new-york/) talk — June 10, 2026.

## What This Is

A progressive, hands-on guide showing how to run Claude Code as an AI agent on Kubernetes — from a simple Job to a fully autonomous developer agent with credential isolation and persistent memory.

## Prerequisites

- Docker
- [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker)
- kubectl
- An Anthropic API key (`ANTHROPIC_API_KEY`)
- A GitHub PAT with `repo` scope (for concepts 04-05)

## Setup

```bash
git clone https://github.com/csantanapr/kcd-new-york-k8s-claude.git
cd kcd-new-york-k8s-claude
cp .env.example .env
# Edit .env and add your real keys
```

## Concepts

| # | Concept | What You Learn |
|---|---------|----------------|
| 01 | [Kind Cluster](./01-kind-cluster/) | Create a local K8s cluster for testing |
| 02 | [Claude K8s Job](./02-claude-k8s-job/) | Run Claude Code as a one-shot Kubernetes Job |
| 03 | [Sidecar Proxy](./03-sidecar-proxy/) | Secure credentials with a proxy sidecar pattern |
| 04 | [Code Reviewer](./04-code-reviewer/) | Autonomous PR reviewer running on a CronJob |
| 05 | [Developer Agent](./05-developer-agent/) | Autonomous developer with persistent memory and session resume |
| 06 | [Future](./06-future/) | E2B sandbox isolation and KRO abstractions (coming soon) |

## Quick Start

```bash
# 1. Set up credentials
cp .env.example .env
# Edit .env with your real API keys

# 2. Create the Kind cluster
cd 01-kind-cluster && bash scripts/create-cluster.sh && cd ..

# 3. Run your first Claude Code job
cd 02-claude-k8s-job && bash scripts/build-and-load.sh
source ../../.env
kubectl create secret generic anthropic-credentials \
  --from-literal=ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY -n claude-demo
kubectl apply -f manifests/job.yaml
kubectl logs -f job/claude-hello -n claude-demo
```

## Notes

- All examples use `claude-haiku-4-5-20251001` model for cost efficiency. Change the model in manifests to use a different one.
- The credential security pattern (sidecar proxy) is introduced in concept 03 and used in all subsequent concepts.
- Default test repo for PR operations: `csantanapr/kcd-nyc-hello` (private).
