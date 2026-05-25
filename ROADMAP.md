# Roadmap

Planned extensions to the platform engineering patterns demonstrated in this repo.

---

## Agent Sandbox Isolation (Implemented — Concept 07)

[`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) provides a `Sandbox` CRD purpose-built for AI agent runtimes on Kubernetes. See [concept 07](./07-sandbox/) for the full implementation.

The RGD supports two modes based on the `schedule` field:

- **No schedule (default)** — a single Sandbox runs Claude Code directly with full Bash access. The sandbox IS the isolation boundary.
- **With schedule** — a CronJob orchestrator creates/waits/deletes Runner CRs on each tick.

## Future Extensions

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
  sandbox: kubernetes   # or: none
```

The RGD would use CEL conditionals to generate the right resources:

| `sandbox` value | What KRO generates |
|---|---|
| `none` | Job + ConfigMap + PVCs (current behavior) |
| `kubernetes` | `Sandbox` CR from agent-sandbox with gVisor runtime class |

This gives developers a single API while the platform team controls the isolation boundary.
