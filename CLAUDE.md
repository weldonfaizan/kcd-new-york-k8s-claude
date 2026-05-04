# CLAUDE.md

## Project

Reference implementation for KCD New York 2026 talk: "Platform Engineering for AI Agents: Secure Claude Code on Kubernetes with KRO"

## Structure

- Each concept is a numbered directory (`01-kind-cluster/`, `02-claude-k8s-job/`, etc.)
- Concepts are progressive — each builds on the previous
- Each concept is self-contained with its own README and manifests
- The numbered prefix is load-bearing — do not reorder

## Conventions

- Kubernetes manifests: lowercase-hyphenated filenames (e.g., `cronjob.yaml`)
- Shell scripts: `*.sh` with shebang `#!/bin/bash` and `set -e`
- Each concept uses its own namespace matching the folder name (e.g., `02-claude-k8s-job`, `03-sidecar-proxy`)
- Secret name: `agent-credentials` in all namespaces (contains `ANTHROPIC_API_KEY` + `GH_TOKEN`)
- Claude Code flags: `-p --dangerously-skip-permissions --verbose --output-format stream-json --model claude-haiku-4-5-20251001`
- Never commit real credentials — use `REPLACE_ME` placeholders in manifests
- Real credentials go in `.env` (gitignored), loaded via `source .env`

## Cluster Setup

`01-kind-cluster/scripts/create-cluster.sh` is idempotent:
- Creates Kind cluster `claude-demo` (skips if exists)
- Creates all concept namespaces
- Creates/recreates `agent-credentials` secret in all namespaces from `.env`
- Re-run anytime to refresh secrets after editing `.env`

## Log Output

All concepts use `stream-json` piped through `jq` for readable logs:

```bash
timeout 3600 claude $CLAUDE_ARGS -- "$PROMPT" \
  | tee "$RAW_LOG" \
  | jq --unbuffered -r '
if .type == "assistant" then
  .message.content[]? |
  if .type == "text" then ">>> " + .text[0:5000]
  elif .type == "tool_use" then "[" + .name + "] " + ((.input | tostring)[0:3000])
  else empty end
elif .type == "result" then
  "[done] " + (.result // "complete")[0:5000]
else empty end' || CLAUDE_EXIT=$?
```

Output format: `>>> ` (text), `[Bash] {...}` (tool calls), `[done] ...` (result).

## Prompts

- Concepts 02-03: prompt delivered via inline env var (`PROMPT`)
- Concepts 04-05: prompt stored in `prompts/*.md`, delivered via ConfigMap volume mount
- Concepts 06-07: prompt inline in CR spec, rendered into ConfigMap by KRO

## README Template (per concept)

Each concept README follows: Concept Summary, Prerequisites, Step-by-Step, How to Verify, Expected Output, Cleanup

## Testing

- Template repo: `csantanapr/kcd-nyc-hello-template` (public, GitHub template) — audience forks this
- Target repo configured via `TESTING_REPO` env var in `.env`, injected into manifests via `envsubst`
- Kind cluster name: `claude-demo`
- Always test with haiku model for cost efficiency

## envsubst Pattern

Manifests use `${TESTING_REPO}` placeholder. Apply with:

```bash
set -a && source .env && set +a
envsubst '$TESTING_REPO' < manifests/configmap.yaml | kubectl apply -f -
```

- `set -a` exports all `.env` vars so `envsubst` can see them
- `'$TESTING_REPO'` restricts substitution to only that variable — embedded `${TARGET_REPO}` shell refs in ConfigMap scripts are preserved

## Feature Cycle (developer + reviewer agents)

A feature goes through this cycle until merged:

1. **Developer** creates a PR implementing the next SPEC.md feature (no tests)
2. **Reviewer** reviews, requests changes (missing tests)
3. **Developer** addresses feedback, adds tests
4. **Reviewer** approves and merges

Run the cycle (concepts 04-05):

```bash
# Apply both configmaps (only needed once, or after changes)
set -a && source .env && set +a
envsubst '$TESTING_REPO' < 04-code-reviewer/manifests/configmap.yaml | kubectl apply -f -
envsubst '$TESTING_REPO' < 05-developer-agent/manifests/configmap.yaml | kubectl apply -f -

# Run developer → wait → run reviewer → wait → repeat until merged
kubectl delete job claude-developer -n 05-developer-agent --ignore-not-found && sleep 5 && kubectl create -f 05-developer-agent/manifests/job.yaml
kubectl wait --for=condition=complete job/claude-developer -n 05-developer-agent --timeout=300s

kubectl delete job claude-reviewer -n 04-code-reviewer --ignore-not-found && sleep 3 && kubectl create -f 04-code-reviewer/manifests/job.yaml
kubectl wait --for=condition=complete job/claude-reviewer -n 04-code-reviewer --timeout=300s
```

To restrict the developer to only address existing PRs (no new features), patch AGENT_TASK:

```bash
kubectl patch configmap developer-config -n 05-developer-agent --type merge \
  -p '{"data":{"AGENT_TASK":"ONLY address review feedback on existing open PRs. Do NOT create new features or PRs."}}'
```

Reset after: `kubectl patch configmap developer-config -n 05-developer-agent --type merge -p '{"data":{"AGENT_TASK":""}}'`
