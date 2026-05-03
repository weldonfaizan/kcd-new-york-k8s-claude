# 05 - Claude Code as Developer Agent

An autonomous developer agent that implements features, submits PRs, and addresses review comments. Uses persistent storage to maintain workspace and Claude memory across pod restarts.

## Concept

```
┌────────────────────────────────────────────────────────────┐
│ Kubernetes Job                                             │
│                                                            │
│  ┌──────────────────────────────┐  ┌────────────────────┐ │
│  │ claude-code container        │  │ proxy sidecar      │ │
│  │                              │  │                    │ │
│  │ 1. Clone/fetch target repo   │  │ Injects:           │ │
│  │ 2. Check for existing PR     │  │ - ANTHROPIC_API_KEY│ │
│  │ 3a. New: implement feature   │  │ - GH_TOKEN       │ │
│  │ 3b. Resume: address comments │  │                    │ │
│  │ 4. Commit, push, open/update │  │                    │ │
│  │    PR                        │  │                    │ │
│  └──────────┬───────────────────┘  └────────────────────┘ │
│             │                                              │
│  ┌──────────▼───────────────────────────────────────────┐  │
│  │ PersistentVolumes                                    │  │
│  │  /workspace (code + git worktrees)                   │  │
│  │  /home/claude/.claude (memory + sessions)            │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Key Features

- **Persistent workspace**: Code and git history survive pod restarts via PVC
- **Session resume**: Claude's memory and session state persist, enabling multi-run workflows
- **PR lifecycle**: Creates PRs, and on subsequent runs addresses review comments
- **Multi-agent**: Works with the Code Reviewer (concept 04) — reviewer leaves comments, developer addresses them

## Prerequisites

- Kind cluster running (see [01-kind-cluster](../01-kind-cluster/))
- Claude Code image loaded (see [02-claude-k8s-job](../02-claude-k8s-job/))
- Proxy image loaded (see [03-sidecar-proxy](../03-sidecar-proxy/))
- `.env` file with both `ANTHROPIC_API_KEY` and `GH_TOKEN` set
- A GitHub repo to develop against (default: `csantanapr/kcd-nyc-hello`)

## Step-by-Step

### 1. Create the PersistentVolumeClaims

```bash
kubectl apply -f manifests/pvc.yaml
```

### 2. Create the Secret

```bash
kubectl create secret generic agent-credentials \
  --from-env-file=../../.env \
  -n claude-demo
```

### 3. Configure the feature request

Edit `manifests/configmap.yaml` to set your `FEATURE_REQUEST`, then apply:

```bash
kubectl apply -f manifests/configmap.yaml
```

### 4. Run the Developer Agent

```bash
kubectl apply -f manifests/job.yaml
```

### 5. Watch the output

```bash
kubectl logs -f job/claude-developer -c claude-code -n claude-demo
```

### 6. Re-run after review comments

After the Code Reviewer (concept 04) or a human leaves comments on the PR, delete the completed job and re-run:

```bash
kubectl delete job claude-developer -n claude-demo
kubectl apply -f manifests/job.yaml
```

The agent will resume its session, read the review comments, and address them.

## How to Verify

1. Check the target repo for a new PR created by the agent
2. The PR should have the sentinel tag `<!-- claude-developer -->` in the body
3. On subsequent runs, verify the agent pushes new commits addressing review comments

## Expected Output (first run)

```
Starting Claude Code Developer Agent...
Target repo: csantanapr/kcd-nyc-hello
Feature: Add a /health endpoint that returns JSON status
---
Cloning csantanapr/kcd-nyc-hello...
Creating branch: claude/feature/health-endpoint
Implementing feature...
Writing tests...
Committing and pushing...
Opening PR #7: "Add /health endpoint returning JSON status"
Done. PR created successfully.
```

## Expected Output (subsequent run with review comments)

```
Starting Claude Code Developer Agent...
Resuming session...
Found existing PR #7 with 2 review comments.
Addressing comment 1: "Add timestamp to health response"
Addressing comment 2: "Include version field"
Committing fixes and pushing...
Done. Addressed 2 review comments.
```

## Cleanup

```bash
kubectl delete -f manifests/job.yaml
kubectl delete -f manifests/configmap.yaml
kubectl delete secret agent-credentials -n claude-demo
# To fully reset (lose workspace and memory):
kubectl delete -f manifests/pvc.yaml
```
