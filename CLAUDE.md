# CLAUDE.md

## Project

Reference implementation for KCD New York 2026 talk: "Platform Engineering for AI Agents: Secure Claude Code on Kubernetes with KRO"

## Structure

- Each concept is a numbered directory (`01-kind-cluster/`, `02-claude-k8s-job/`, etc.)
- Concepts are progressive — each builds on the previous
- Each concept is self-contained with its own README and manifests
- The numbered prefix is load-bearing — do not reorder
- `proxy/` — standalone transparent credential proxy (Go binary, used by concepts 03-08)
- Proxy Docker build: `make build-proxy` (from project root, builds `proxy/`)

## Conventions

- Kubernetes manifests: lowercase-hyphenated filenames (e.g., `cronjob.yaml`)
- Shell scripts: `*.sh` with shebang `#!/bin/bash` and `set -e`
- Each concept uses its own namespace matching the folder name (e.g., `02-claude-k8s-job`, `03-sidecar-proxy`)
- Secret name: `agent-credentials` in all namespaces (contains `GH_TOKEN`; also `ANTHROPIC_API_KEY` in api-key mode)
- Claude Code flags: `-p --dangerously-skip-permissions --verbose --output-format stream-json --model ${ANTHROPIC_MODEL}`
- Model set via `ANTHROPIC_MODEL` in `.env` — Bedrock: `us.anthropic.claude-haiku-4-5-20251001-v1:0`, API-key: `claude-haiku-4-5-20251001`
- Never commit real credentials — use `REPLACE_ME` placeholders in manifests
- Real credentials go in `.env` (gitignored), loaded via `source .env`

## Cluster Setup

`01-kind-cluster/scripts/create-cluster.sh` is idempotent:
- Creates Kind cluster `claude-demo` (skips if exists)
- Creates all concept namespaces
- Creates/recreates `agent-credentials` secret in all namespaces from `.env`
- Re-run anytime to refresh secrets or restart the metadata server

### Authentication Modes

Controlled by `AUTH_MODE` env var (default: `bedrock`):

- **`bedrock`** (default): Uses `aws-vault --ec2-server` to expose an EC2 metadata endpoint. Pods get temporary AWS credentials automatically and authenticate to Claude via Amazon Bedrock. Requires `aws-vault`, `socat`, and a profile with `bedrock:InvokeModel` permissions. Pods must set `CLAUDE_CODE_USE_BEDROCK=1` and `AWS_REGION=us-west-2`.
- **`api-key`**: Injects `ANTHROPIC_API_KEY` from `.env` into Kubernetes Secrets (original behavior).

```bash
# Default (Bedrock)
bash 01-kind-cluster/scripts/create-cluster.sh

# API key mode
AUTH_MODE=api-key bash 01-kind-cluster/scripts/create-cluster.sh

# Custom aws-vault profile
AWS_VAULT_PROFILE=my-profile bash 01-kind-cluster/scripts/create-cluster.sh
```

The Bedrock metadata server dies when the terminal closes — re-run the script to restart.

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
- Concepts 06-08: prompt inline in CR spec, rendered into ConfigMap by KRO

## README Template (per concept)

Each concept README follows: Concept Summary, Prerequisites, Step-by-Step, How to Verify, Expected Output, Cleanup

## Testing

### E2E Test Suite

```bash
make test          # Run all tests (02, 03, 06, 07, 08)
make test-02       # Simple job
make test-03       # Sidecar proxy
make test-06       # KRO agent (requires KRO installed)
make test-07       # Sandbox (requires KRO + agent-sandbox CRD)
make test-08       # SandboxTemplate (requires KRO + agent-sandbox extensions)
```

Tests 06 and 07 gracefully SKIP if their CRDs aren't installed. Each test creates a job, waits for completion, and prints output summary.

Prerequisites for full suite:
- Cluster running: `make all` (builds images, creates cluster, loads images)
- KRO installed: `helm install kro oci://registry.k8s.io/kro/charts/kro --namespace kro-system --create-namespace`
- Agent-sandbox installed (for test-07, test-08): see `07-sandbox/README.md` step 3
- Agent-sandbox extensions (for test-08): included in v0.4.6 manifest

### Feature Cycle Testing (concepts 04-05)

- Template repo: `csantanapr/kcd-nyc-hello-template` (public, GitHub template) — audience forks this
- Target repo configured via `TESTING_REPO` env var in `.env`, injected into manifests via `envsubst`
- Kind cluster name: `claude-demo`
- Always test with haiku model for cost efficiency

## envsubst Pattern

Manifests use `${TESTING_REPO}`, `${CLAUDE_CODE_USE_BEDROCK}`, `${AWS_REGION}`, `${ANTHROPIC_API_KEY_PLACEHOLDER}`, and `${ANTHROPIC_MODEL}` placeholders. Apply with:

```bash
set -a && source .env && set +a
envsubst '$TESTING_REPO $CLAUDE_CODE_USE_BEDROCK $AWS_REGION $ANTHROPIC_API_KEY_PLACEHOLDER $ANTHROPIC_MODEL' < manifests/job.yaml | kubectl apply -f -
```

- `set -a` exports all `.env` vars so `envsubst` can see them
- Restrict substitution to listed variables — embedded `${TARGET_REPO}` shell refs in ConfigMap scripts are preserved
- Bedrock mode: `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION=us-west-2`, `ANTHROPIC_API_KEY_PLACEHOLDER=`
- API-key mode: `CLAUDE_CODE_USE_BEDROCK=`, `AWS_REGION=`, `ANTHROPIC_API_KEY_PLACEHOLDER=FAKE_KEY_REPLACED_BY_PROXY`

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
