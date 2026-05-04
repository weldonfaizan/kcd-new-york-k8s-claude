# Roadmap

Planned extensions to the platform engineering patterns demonstrated in this repo.

---

## Agent Sandbox Isolation

Run Claude Code agents inside isolated sandboxes so that generated bash commands cannot affect the host pod, other containers, or the cluster.

### Kubernetes Agent Sandbox (Implemented — Concept 07)

[`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) provides a `Sandbox` CRD purpose-built for AI agent runtimes on Kubernetes. See [concept 07](./07-sandbox/agent-sandbox/) for the full implementation.

The RGD supports two modes based on the `schedule` field:

- **No schedule (default)** — a single Sandbox runs Claude Code directly with full Bash access. The sandbox IS the isolation boundary. Simplest setup with `volumeClaimTemplates` for persistence.
- **With schedule** — a CronJob provides scheduling with a separate Sandbox as the execution backend. `--disallowedTools Bash` removes the built-in Bash tool, replaced by an MCP server (`sandbox_execute`) that routes git/gh locally and everything else to the Sandbox's HTTP API.

### E2B Remote Sandbox

[E2B](https://e2b.dev/) provides cloud-hosted ephemeral sandboxes. Using Claude Code's **PreToolUse hooks**, bash commands are intercepted before execution and forwarded to an E2B sandbox:

```
Claude Code wants to run: npm test
       |
       v
PreToolUse Hook fires
       |
       v
Hook modifies command: e2b-run "npm test"
       |
       v
Local bash runs the wrapper
       |
       v
Wrapper creates E2B sandbox, runs command, returns output
       |
       v
Claude sees results as if they ran locally
```

File operations (Read/Write/Edit) remain local. Only bash execution is sandboxed.

### KRO as the Sandbox Abstraction Layer

The `ClaudeCodeAgent` RGD from concept 06 can be extended with a `sandbox` field that lets the platform team choose the isolation strategy per agent:

```yaml
apiVersion: kro.run/v1alpha1
kind: ClaudeCodeAgent
metadata:
  name: claude-developer
spec:
  repo: myuser/kcd-nyc-hello
  prompt: |
    ...
  sandbox: kubernetes   # or: e2b, none
```

The RGD would use CEL conditionals to generate the right resources:

| `sandbox` value | What KRO generates |
|---|---|
| `none` | Job + ConfigMap + PVCs (current behavior) |
| `kubernetes` | `Sandbox` CR from agent-sandbox with gVisor runtime class |
| `e2b` | Job with PreToolUse hook config pointing to E2B |

This gives developers a single API while the platform team controls the isolation boundary.
