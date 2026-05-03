# 06 - Future Concepts

These concepts are planned extensions to the platform engineering patterns demonstrated in this repo.

---

## E2B Sandbox for Bash Tool Isolation (Coming Soon)

Instead of Claude Code running bash commands directly inside the pod, route all code execution to an [E2B](https://e2b.dev/) remote sandbox.

### Why

Defense in depth — even if the agent is compromised or generates dangerous commands, it cannot affect the host pod's filesystem, network, or other containers. The sandbox is ephemeral and isolated.

### How

Using Claude Code's **PreToolUse hooks**, bash commands are intercepted before execution and forwarded to an E2B sandbox:

```
Claude Code wants to run: npm test
       │
       ▼
PreToolUse Hook fires
       │
       ▼
Hook modifies command: e2b-run "npm test"
       │
       ▼
Local bash runs the wrapper
       │
       ▼
Wrapper creates E2B sandbox, runs command, returns output
       │
       ▼
Claude sees results as if they ran locally
```

File operations (Read/Write/Edit) remain local. Only bash execution is sandboxed.

---

## KRO Abstraction (Coming Soon)

[KRO (Kube Resource Orchestrator)](https://kro.run/) allows defining custom resource abstractions. This concept will introduce a `ClaudeCodeAgent` custom resource that encapsulates the two-container pattern (main + proxy sidecar) behind a simple, opinionated API.

### Why

Platform teams can expose a controlled, secure-by-default interface for developers to run Claude Code agents without needing to understand the sidecar proxy, PVC, or credential injection implementation.

### What It Would Look Like

```yaml
apiVersion: kro.run/v1alpha1
kind: ClaudeCodeAgent
metadata:
  name: my-feature-developer
  namespace: claude-demo
spec:
  type: developer        # or "reviewer"
  model: claude-haiku-4-5-20251001
  repo: csantanapr/kcd-nyc-hello
  prompt: "Add a /metrics endpoint with Prometheus format"
  schedule: ""           # Empty = one-shot Job, cron expression = CronJob
  persistence:
    workspace: true
    memory: true
  credentials:
    secretRef: agent-credentials
```

This single resource would expand into the full Job + Sidecar + PVC + ConfigMap setup automatically.
