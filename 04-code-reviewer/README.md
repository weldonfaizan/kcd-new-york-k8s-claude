# 04 - Claude Code as Code Reviewer

An autonomous code review agent that runs on a CronJob, checks for open PRs, reviews them, and merges when appropriate.

## Concept

```
┌─────────────────────────────────────────────────────────┐
│ CronJob (every 4 hours)                                 │
│                                                         │
│  ┌─────────────────────────┐  ┌──────────────────────┐ │
│  │ claude-code container   │  │ proxy sidecar        │ │
│  │                         │  │                      │ │
│  │ 1. Clone target repo    │  │ Injects:             │ │
│  │ 2. List open PRs        │  │ - ANTHROPIC_API_KEY  │ │
│  │ 3. Skip already reviewed│  │ - GH_TOKEN         │ │
│  │ 4. Review new PRs       │  │                      │ │
│  │ 5. Comment or merge     │  │                      │ │
│  └─────────────────────────┘  └──────────────────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
   GitHub (via gh CLI)          api.anthropic.com
```

## Key Features

- **Idempotent**: Already-reviewed PRs are skipped (detected via sentinel comment)
- **Scheduled**: Runs automatically every 4 hours via CronJob
- **Secure**: Both Anthropic API key and GitHub token (`GH_TOKEN`) are secured via sidecar proxy
- **Autonomous**: Reviews, comments, and merges without human intervention

## Prerequisites

- Kind cluster running (see [01-kind-cluster](../01-kind-cluster/))
- Claude Code image loaded (see [02-claude-k8s-job](../02-claude-k8s-job/))
- Proxy image loaded (see [03-sidecar-proxy](../03-sidecar-proxy/))
- `.env` file with both `ANTHROPIC_API_KEY` and `GH_TOKEN` set
- `TESTING_REPO` set in `.env` (see [Target Repo Setup](../README.md#target-repo-setup))

## Step-by-Step

### 1. Create the Secret

```bash
kubectl create secret generic agent-credentials \
  --from-env-file=../../.env \
  -n claude-demo
```

### 2. Apply the ConfigMap and run the Job
The set command must be run from inside manifest folder.

```bash
set -a && source ../../.env && set +a
envsubst '$TESTING_REPO' < manifests/configmap.yaml | kubectl apply -f -
kubectl apply -f manifests/job.yaml
```

### 3. Watch the output

```bash
kubectl logs -f job/claude-reviewer -c claude-code -n claude-demo
```

### 4. Re-run (delete completed job and re-apply)

```bash
kubectl delete job claude-reviewer -n claude-demo
kubectl apply -f manifests/job.yaml
```

> **Scheduled use**: `manifests/cronjob.yaml` is also provided if you want the reviewer to run automatically on a schedule (e.g., every 4 hours).

## How to Verify

1. After the job completes, check the target repo for new review comments with the sentinel tag `<!-- claude-reviewer -->`

2. Verify the agent skips already-reviewed PRs (those with both `<!-- claude-reviewer -->` and "Approved") on subsequent runs

## Expected Output

```
Cloning csantanapr/kcd-nyc-hello...
Found 2 open PRs.
PR #3: Already reviewed. Skipping.
PR #5: Reviewing...
  - Code looks good, no issues found.
  - Approving and merging PR #5.
Done. Reviewed 1 PR, skipped 1.
```

## Cleanup

```bash
kubectl delete -f manifests/job.yaml
kubectl delete -f manifests/configmap.yaml
kubectl delete secret agent-credentials -n claude-demo
```
