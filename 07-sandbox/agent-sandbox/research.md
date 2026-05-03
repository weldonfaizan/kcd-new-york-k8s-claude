# Agent Sandbox Research

Research findings on [`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox) v0.4.3.

## What It Is

A Kubernetes SIG Apps project providing a `Sandbox` CRD purpose-built for AI agent runtimes. Each agent runs in its own isolated pod with lifecycle management, persistent storage, and optional kernel-level isolation via gVisor.

- **API Group**: `agents.x-k8s.io/v1alpha1`
- **Kind**: `Sandbox`
- **Scope**: Namespaced

## Installation on Kind

```bash
export VERSION="v0.4.3"

# Core controller + Sandbox CRD
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/manifest.yaml

# Optional: Extensions (SandboxTemplate, SandboxClaim, SandboxWarmPool)
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/extensions.yaml

# Wait for controller
kubectl wait --for=condition=Available deploy -n agent-sandbox-system --all --timeout=60s
```

## Sandbox CRD Spec

```yaml
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: my-sandbox
spec:
  # REQUIRED — full corev1.PodSpec
  podTemplate:
    metadata:        # optional: only labels + annotations (no name)
      labels: {}
      annotations: {}
    spec:            # REQUIRED — full corev1.PodSpec (all fields accepted)

  # OPTIONAL — PVC templates (like StatefulSet)
  volumeClaimTemplates:
    - metadata:
        name: workspace     # volume name in pod
      spec:                  # corev1.PersistentVolumeClaimSpec

  # OPTIONAL — lifecycle
  shutdownTime: "2025-12-31T23:59:59Z"  # RFC3339 expiry timestamp
  shutdownPolicy: Retain                 # Retain (default) or Delete

  # OPTIONAL — pause/resume
  replicas: 1                            # 0 or 1 only; default=1
```

### Key Fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `podTemplate.spec` | `corev1.PodSpec` | **required** | Full upstream PodSpec — `containers`, `initContainers`, `volumes`, `runtimeClassName`, etc. |
| `podTemplate.metadata` | labels + annotations | optional | No `name` field — pod is named after the Sandbox |
| `volumeClaimTemplates` | `[]PVCTemplate` | optional | PVC naming: `{vct.name}-{sandbox.name}` |
| `shutdownTime` | `*metav1.Time` | nil | Absolute expiry timestamp |
| `shutdownPolicy` | string | `Retain` | `Retain` keeps Sandbox object on expiry; `Delete` removes it |
| `replicas` | `*int32` | `1` | 0 = pause (pod deleted, PVCs kept); 1 = running |

### PVC Naming Convention

PVC name = `{volumeClaimTemplate.metadata.name}-{sandbox.metadata.name}`

For a Sandbox named `claude-developer-sandbox` with a VCT named `workspace`, the PVC is `workspace-claude-developer-sandbox`.

The controller automatically injects a `PersistentVolumeClaim`-backed volume with the VCT's short name into the pod spec, overriding any volume with the same name in `podTemplate.spec.volumes`.

### Pod Termination (`restartPolicy: Never`)

When a pod reaches `Succeeded` or `Failed` phase:

1. Controller sets `Finished` condition on Sandbox status (reason: `PodSucceeded` or `PodFailed`)
2. `Ready` condition goes to `False`
3. Pod remains in terminal state — controller does NOT create a replacement
4. Sandbox object and PVCs persist

To re-run: delete the Sandbox CR and recreate it. The PVCs will be recreated too (they're owned by the Sandbox).

### Replicas (Pause/Resume)

- `replicas: 1` — controller ensures a pod exists
- `replicas: 0` — controller deletes the pod, keeps PVCs and Service
- Exposed as a `scale` subresource (compatible with `kubectl scale`)

### Labels Applied by Controller

- `agents.x-k8s.io/sandbox-name-hash: <FNV-1a hex hash>` — primary selector on pod and service
- User labels from `podTemplate.metadata.labels` are propagated to pod
- Controller creates a headless Service (ClusterIP: None) giving stable DNS: `{name}.{namespace}.svc.cluster.local`

### Status

```yaml
status:
  serviceFQDN: my-sandbox.default.svc.cluster.local
  service: my-sandbox
  replicas: 1
  labelSelector: agents.x-k8s.io/sandbox-name-hash=abc12345
  podIPs:
    - 10.244.0.5
  conditions:
    - type: Ready      # True when pod is Running+Ready
    - type: Finished   # True when pod Succeeded/Failed
```

## gVisor Integration

gVisor provides kernel-level isolation via the `runsc` runtime. To use it:

1. Install gVisor on cluster nodes (Linux only — does NOT work on macOS/Kind)
2. Create a RuntimeClass:
   ```yaml
   apiVersion: node.k8s.io/v1
   kind: RuntimeClass
   metadata:
     name: gvisor
   handler: runsc
   ```
3. Set `runtimeClassName: gvisor` in `podTemplate.spec`

On macOS/Kind clusters, omit `runtimeClassName` — the default container runtime provides process-level isolation only.

## Extension CRDs

Installed separately via `extensions.yaml`. All use group `extensions.agents.x-k8s.io/v1alpha1`.

### SandboxTemplate

Reusable template for creating Sandboxes. Used by SandboxClaim and SandboxWarmPool.

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxTemplate
metadata:
  name: claude-agent-template
spec:
  podTemplate: { ... }            # Same as Sandbox.spec.podTemplate
  volumeClaimTemplates: [...]     # Same as Sandbox
  networkPolicy: { ... }          # Optional custom NetworkPolicy rules
  networkPolicyManagement: Managed # Managed (default, applies deny policy) or Unmanaged
  envVarsInjectionPolicy: Disallowed # Allowed, Overrides, or Disallowed
```

When `networkPolicyManagement: Managed` and no custom `networkPolicy` is provided, the controller applies a strict default deny policy (ingress: only from sandbox router; egress: public internet only, blocks RFC1918).

### SandboxClaim

Request a Sandbox from a template (like PVC claiming a PV).

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxClaim
metadata:
  name: my-claim
spec:
  sandboxTemplateRef:
    name: claude-agent-template
  lifecycle:
    shutdownTime: "2025-12-31T23:59:59Z"
    ttlSecondsAfterFinished: 3600
    shutdownPolicy: Retain  # or Delete, DeleteForeground
  warmpool: default  # none, default, or specific pool name
  env:
    - name: MY_VAR
      value: my-value
      containerName: claude-code  # optional, defaults to first container
```

### SandboxWarmPool

Pre-warmed pool of Sandboxes for instant allocation (no cold-start delay).

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxWarmPool
metadata:
  name: claude-pool
spec:
  replicas: 3
  sandboxTemplateRef:
    name: claude-agent-template
  updateStrategy:
    type: OnReplenish  # or Recreate
```

## Architecture: MCP-Based Sandbox Isolation with Smart Routing

Concept 07 keeps Claude Code running as a Job (same as concepts 04-06) but replaces the Bash tool with an MCP server that **routes commands** — whitelisted commands (git, gh) run locally, everything else runs in the Sandbox pod via the SDK-compatible HTTP API.

```
┌──────────────────────────────────────────────┐
│  Job Pod (Claude Code CLI)                   │
│                                              │
│  ┌──────────────┐  ┌──────────────────────┐  │
│  │ proxy-sidecar│  │ claude-code          │  │
│  │ (credentials)│  │                      │  │
│  │              │  │ Claude CLI           │  │
│  │ ANTHROPIC_KEY│  │  ├─ Read/Write/Edit  │  │
│  │ GH_TOKEN     │  │  ├─ Glob/Grep       │  │
│  │              │  │  └─ MCP: sandbox     │  │
│  └──────────────┘  │    (no Bash tool)    │  │
│                    │                      │  │
│                    │  sandbox_execute ─────┼──┤
│                    │   ├─ git/gh → LOCAL  │  │
│                    │   └─ other → SANDBOX ─┼──┼── HTTP ──┐
│                    └──────────────────────┘  │          │
│                                              │          │
│  Volumes: /workspace (shared PVC)            │          │
│           /home/claude/.claude (memory PVC)   │          │
└──────────────────────────────────────────────┘          │
                                                          │
┌──────────────────────────────────────────────┐          │
│  Sandbox Pod (Isolated Execution)            │◄─────────┘
│                                              │
│  SDK-compatible FastAPI runtime (:8888)      │
│   POST /execute  → subprocess.run()          │
│   POST /upload   → save file                 │
│   GET  /download → retrieve file             │
│   GET  /list     → directory listing         │
│   GET  /exists   → file existence check      │
│                                              │
│  Has: git, gh, node, python3, go             │
│  GH_TOKEN (real, from Secret)                │
│  DNS: {name}-sandbox.{ns}.svc.cluster.local  │
│                                              │
│  Volumes: /workspace (own PVC)               │
└──────────────────────────────────────────────┘
```

### Key Design Decisions

1. **`--disallowedTools Bash`** removes the built-in Bash tool, replaced by MCP `sandbox_execute`
2. **Smart routing** — the MCP server checks the command's first word against a configurable whitelist (`ALLOWED_LOCAL_COMMANDS`). Whitelisted commands (git, gh) run locally for speed and credential access. Everything else runs in the sandbox.
3. **SDK-compatible runtime** — the Sandbox pod implements the same HTTP API as the official `python-runtime-sandbox` from kubernetes-sigs/agent-sandbox (execute, upload, download, list, exists). The official Python SDK works against this server without changes.
4. **Automatic file sync** — before sandbox execution, the MCP server tars the local workspace and uploads it via the SDK's upload endpoint. After execution, results are synced back. This uses the same file transfer pattern as the SDK's `Filesystem` class.
5. **Credential separation** — Anthropic API key stays in the Job pod (via proxy sidecar). GH_TOKEN goes to the Sandbox pod for git operations. Git/gh run locally through the proxy.
6. **Configurable whitelist** — the RGD schema's `allowedLocalCommands` field lets platform teams control which commands run locally per agent.

### Python SDK Compatibility

The sandbox runtime implements the same endpoints as the official agent-sandbox Python runtime:

| Endpoint | SDK Class | Method |
|---|---|---|
| `POST /execute` | `CommandExecutor` | `sandbox.commands.run(command)` |
| `POST /upload` | `Filesystem` | `sandbox.files.write(path, content)` |
| `GET /download/{path}` | `Filesystem` | `sandbox.files.read(path)` |
| `GET /list/{path}` | `Filesystem` | `sandbox.files.list(path)` |
| `GET /exists/{path}` | `Filesystem` | `sandbox.files.exists(path)` |

To use the official SDK instead of raw HTTP, install from git:

```bash
pip install git+https://github.com/kubernetes-sigs/agent-sandbox.git#subdirectory=clients/python/agentic-sandbox-client
```

Then use `SandboxInClusterConnectionConfig(server_port=8888)` for in-cluster connectivity.

### Validated via Docker Testing

```bash
# FastMCP + --disallowedTools Bash confirmed working in container
docker run --rm --entrypoint bash \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -v sandbox_mcp.py:/mcp/server.py:ro \
  -v mcp-config.json:/mcp/config.json:ro \
  claude-code:latest \
  -c 'claude -p --dangerously-skip-permissions --verbose \
    --model claude-haiku-4-5-20251001 \
    --disallowedTools Bash --mcp-config /mcp/config.json \
    -- "Use sandbox_execute to run: echo hello"'
```

Result: `mcp_servers: [{"name":"sandbox","status":"connected"}]`, Bash absent from tools list, `sandbox_execute` called successfully.

## Key Differences from Concept 06 (KRO Job)

| Aspect | Concept 06 (Job) | Concept 07 (Sandbox) |
|---|---|---|
| Bash execution | Direct, in Job pod | Smart routing: git/gh local, rest → Sandbox |
| Isolation | None | Code execution in separate Sandbox pod |
| File operations | Local filesystem | Local Read/Write/Edit + sandbox sync for execution |
| PVC management | Standalone PVCs | Sandbox `volumeClaimTemplates` + standalone memory PVC |
| Credentials | Proxy handles API + git | Proxy for API; git local via proxy; GH_TOKEN direct to Sandbox |
| Scheduling | CronJob support | One-shot Job only |
| Sandbox runtime | N/A | SDK-compatible FastAPI (execute, upload, download, list, exists) |
| Kernel isolation | Not available | `runtimeClassName: gvisor` (Linux only) |
