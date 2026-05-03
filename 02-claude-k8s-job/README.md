# 02 - Claude Code as a Kubernetes Job

Run Claude Code CLI as a one-shot Kubernetes Job. The simplest way to get Claude Code running on K8s.

## Concept

```
┌─────────────────────────────────────┐
│ Kubernetes Job                      │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ claude-code container       │    │
│  │                             │    │
│  │ ANTHROPIC_API_KEY (Secret)  │    │
│  │ CLAUDE_PROMPT (env var)     │    │
│  │                             │    │
│  │ claude -p -- $PROMPT        │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
         │
         ▼ stdout (stream-json) → kubectl logs
```

## Manifest Walkthrough

Here is the full Job manifest with each part explained:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: claude-hello
  namespace: claude-demo
spec:
  backoffLimit: 0          # Don't retry on failure — Claude is not idempotent
  template:
    spec:
      restartPolicy: Never # Same reason: one shot, no restarts
      containers:
        - name: claude-code
          image: claude-code:latest
          imagePullPolicy: Never   # Image was loaded directly into Kind, not in a registry

          # The full non-interactive Claude invocation.
          # $(VAR) syntax is Kubernetes env var substitution — resolved before the process starts.
          command:
            - claude
            - -p                             # Non-interactive: print response and exit
            - --dangerously-skip-permissions # Headless: skip interactive permission prompts
            - --verbose                      # Emit detailed event stream
            - --output-format
            - stream-json                    # Structured JSON output, one event per line
            - --model
            - $(ANTHROPIC_MODEL)             # Pinned model, resolved from env below
            - --                             # Separator: everything after is the prompt
            - $(CLAUDE_PROMPT)               # The prompt, resolved from env below

          env:
            - name: ANTHROPIC_MODEL
              value: "claude-haiku-4-5-20251001"
            - name: CLAUDE_PROMPT
              value: "Print all environment variables you can see"

          # Injects all keys from the Secret as env vars.
          # The Secret holds ANTHROPIC_API_KEY, which Claude Code reads automatically.
          envFrom:
            - secretRef:
                name: anthropic-credentials

          resources:          # Always set limits on agent workloads
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

Key design decisions:
- **`backoffLimit: 0` + `restartPolicy: Never`** — Claude jobs are not safe to retry blindly; they may have already taken actions (API calls, git pushes, etc.)
- **`$(VAR)` substitution** — Kubernetes resolves env var references in `command` before launching the container, so `CLAUDE_PROMPT` and `ANTHROPIC_MODEL` are expanded without any shell wrapper
- **`envFrom.secretRef`** — keeps the API key out of the manifest itself; the Secret is created separately and never checked in

## How Claude Runs Non-Interactively

Claude Code supports a headless, one-shot mode. The key flags:

```
claude -p --dangerously-skip-permissions --verbose --output-format stream-json --model <model> -- "<prompt>"
```

| Flag | Purpose |
|------|---------|
| `-p` | Non-interactive mode: print response to stdout and exit |
| `--dangerously-skip-permissions` | Skip interactive permission prompts (required for headless use) |
| `--verbose` | Emit the full event stream (tool calls, results, thinking) |
| `--output-format stream-json` | Structured JSON output, one event per line — ideal for log parsing |
| `--model` | Explicitly pin the model — never rely on defaults in automation |
| `--` | Argument separator: everything after is treated as the prompt positional argument |

> `ANTHROPIC_API_KEY` in the environment is sufficient for auth — no login or OAuth required.

## Where the Prompt Comes From

In this concept the prompt is hardcoded inline in the Job spec as the `CLAUDE_PROMPT` environment variable, passed after `--`:

```yaml
command:
  - claude
  - -p
  - --dangerously-skip-permissions
  - --verbose
  - --output-format
  - stream-json
  - --model
  - $(ANTHROPIC_MODEL)
  - --
  - $(CLAUDE_PROMPT)        # <-- injected from env var below
env:
  - name: ANTHROPIC_MODEL
    value: "claude-haiku-4-5-20251001"
  - name: CLAUDE_PROMPT
    value: "Print all environment variables you can see"
```

The API key comes from a Kubernetes Secret mounted via `envFrom`:

```yaml
    envFrom:
      - secretRef:
          name: anthropic-credentials   # holds ANTHROPIC_API_KEY
```

> This inline-prompt pattern works for simple one-liners. Concepts 04 and 05 move to longer prompts stored in `prompts/*.md` files, delivered via ConfigMap volume mounts.

## Prerequisites

- Kind cluster running (see [01-kind-cluster](../01-kind-cluster/))
- `.env` file with `ANTHROPIC_API_KEY` set

## Step-by-Step

### 1. Build and load the Docker image

```bash
bash scripts/build-and-load.sh
```

### 2. Create the Secret from your .env

```bash
kubectl create secret generic anthropic-credentials \
  --from-env-file=../../.env \
  -n claude-demo
```

### 3. Run the Job

```bash
kubectl apply -f manifests/job.yaml
```

### 4. Watch the output

```bash
kubectl logs -f job/claude-hello -n claude-demo
```

The output is stream-json. To extract just the final result:

```bash
kubectl logs job/claude-hello -n claude-demo | grep '"type":"result"' | jq -r '.result'
```

## How to Verify

Claude Code should print all environment variables it can see. You'll notice `ANTHROPIC_API_KEY` is visible in the output — this is the security issue that concept 03 addresses.

## Expected Output

```json
{"type":"system","subtype":"init","session_id":"...","apiKeySource":"ANTHROPIC_API_KEY",...}
{"type":"assistant","message":{...},...}
{"type":"result","subtype":"success","result":"Here are the environment variables:\nANTHROPIC_API_KEY=sk-ant-...","total_cost_usd":0.012,...}
```

## Security Note

In this setup, the API key is injected as an environment variable. Any tool Claude runs inherits the container's environment — a compromised tool could exfiltrate `ANTHROPIC_API_KEY` silently.

See [03-sidecar-proxy](../03-sidecar-proxy/) for the secure pattern.

## Cleanup

```bash
kubectl delete -f manifests/job.yaml
kubectl delete secret anthropic-credentials -n claude-demo
```
