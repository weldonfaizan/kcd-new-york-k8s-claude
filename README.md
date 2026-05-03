# Platform Engineering for AI Agents: Secure Claude Code on Kubernetes with KRO

Reference implementation for the [KCD New York](https://community.cncf.io/kcd-new-york/) talk — June 10, 2026.

## What This Is

A progressive, hands-on guide showing how to run Claude Code as an AI agent on Kubernetes — from a simple Job to a fully autonomous developer agent with credential isolation and persistent memory.

## Prerequisites

- Docker
- [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker)
- kubectl
- `envsubst` (included with `gettext` — pre-installed on most systems)
- An Anthropic API key (`ANTHROPIC_API_KEY`)
- A GitHub PAT with write access to your target repo (see [Target Repo Setup](#target-repo-setup))

## Setup

```bash
git clone https://github.com/csantanapr/kcd-new-york-k8s-claude.git
cd kcd-new-york-k8s-claude
cp .env.example .env
# Edit .env and add your real keys
```

## Target Repo Setup

Concepts 04-06 need a GitHub repo to operate on. Create one from the template:

1. Go to [`csantanapr/kcd-nyc-hello-template`](https://github.com/csantanapr/kcd-nyc-hello-template) and click **"Use this template"** → **"Create a new repository"**
2. Name it whatever you like (e.g., `kcd-nyc-hello`) and make it **private** or **public**
3. Create a **GitHub Personal Access Token** (fine-grained) with access to your new repo:
   - Go to **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
   - Set **Repository access** to **"Only select repositories"** and pick your new repo
   - Under **Repository permissions**, grant:
     - **Contents**: Read and write (clone, push)
     - **Pull requests**: Read and write (create, comment, merge PRs)
     - **Metadata**: Read-only (required by default)
4. Set both values in your `.env`:
   ```bash
   # .env
   GH_TOKEN=github_pat_REPLACE_ME
   TESTING_REPO=YOUR_USERNAME/kcd-nyc-hello
   ```

Manifests use `envsubst` to inject the repo at apply-time — no manual YAML editing needed:
```bash
set -a && source .env && set +a
envsubst '$TESTING_REPO' < manifests/configmap.yaml | kubectl apply -f -
```
`set -a` exports all variables so `envsubst` can see them. The `'$TESTING_REPO'` argument restricts substitution to only that variable, leaving other `${}` references (used by shell scripts inside ConfigMaps) untouched. See each concept's README for the exact apply commands.

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
- Target repo for PR operations is configured via `TESTING_REPO` in `.env` (see [Target Repo Setup](#target-repo-setup)).
