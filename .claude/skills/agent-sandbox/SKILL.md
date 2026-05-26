---
name: agent-sandbox
description: Write Sandbox CRDs for kubernetes-sigs/agent-sandbox. Use when creating Sandbox resources, SandboxTemplates, SandboxClaims, SandboxWarmPools, volumeClaimTemplates, NetworkPolicy management, or integrating Sandbox with KRO RGDs.
allowed-tools: Read, Grep, Glob
---

# Agent Sandbox CRD Reference

Version: v0.4.6

## Core CRD: Sandbox

API Group: `agents.x-k8s.io/v1alpha1`
Kind: `Sandbox`
Scope: Namespaced

### Sandbox Spec — All Fields

```yaml
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: my-sandbox
  namespace: default
spec:
  # REQUIRED — pod definition
  podTemplate:
    metadata:                          # Optional: only labels + annotations
      labels:
        my-label: value
      annotations:
        my-annotation: value
    spec:                              # REQUIRED — full corev1.PodSpec
      restartPolicy: Never             # Recommended for one-shot agents
      runtimeClassName: gvisor         # Optional, Linux-only
      containers:
        - name: main
          image: my-image:latest
      initContainers:                  # Native sidecars supported
        - name: sidecar
          image: sidecar:latest
          restartPolicy: Always
      volumes: [...]                   # Standard volume definitions

  # OPTIONAL — PVC templates (owned by the Sandbox CR)
  volumeClaimTemplates:
    - metadata:
        name: workspace                # Volume name — referenced in volumeMounts
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi

  # OPTIONAL — lifecycle
  replicas: 1                          # 0 or 1 only (default: 1)
  shutdownTime: "2025-12-31T23:59:59Z" # RFC3339 expiry
  shutdownPolicy: Retain               # Retain (default) or Delete

  # OPTIONAL — headless Service
  service: true                        # opt-in: creates headless Service for stable DNS
```

### volumeClaimTemplates

#### Naming

PVC name = `{vct.metadata.name}-{sandbox.metadata.name}`

Example: VCT `workspace` + Sandbox `claude-dev-sandbox` → PVC `workspace-claude-dev-sandbox`

#### Volume Injection

The controller automatically injects a volume with the VCT's short name (`workspace`) into the pod, pointing to the generated PVC. You only need to define `volumeMounts` in your containers — no need to define matching `volumes` in `podTemplate.spec.volumes`.

#### Ownership and Lifecycle (CRITICAL)

PVCs created from `volumeClaimTemplates` are **owned by the Sandbox CR** via `ownerReference` with `controller: true`. This has important implications:

| Action | PVC Behavior |
|--------|-------------|
| Container exits, Sandbox CR stays (`shutdownPolicy: Retain`) | PVCs **stay** (owner still exists) |
| Sandbox CR deleted (any reason) | PVCs **cascade-deleted** by Kubernetes GC |
| `kubectl delete sandbox X --cascade=orphan` | PVCs **orphaned** (survive, ownerRef removed) |
| New Sandbox created, finds orphaned PVC | PVC **re-adopted** (ownerRef added back) |

**Key insight**: You CANNOT delete and recreate a Sandbox to reuse PVCs in normal flow. Deleting the Sandbox cascades to PVCs. Use one of these patterns instead:

1. **Keep Sandbox alive** — with `shutdownPolicy: Retain`, the Sandbox CR stays after container exit. PVCs persist.
2. **Orphan delete** — `kubectl delete sandbox X --cascade=orphan` then recreate with same name. Controller finds unowned PVCs and re-adopts them.
3. **Standalone PVCs** — create PVCs independently (not via volumeClaimTemplates), mount them via `podTemplate.spec.volumes`. No ownership cascade.

#### When to use volumeClaimTemplates vs standalone PVCs

| Use Case | Approach |
|----------|----------|
| Ephemeral sandbox (no persistence needed) | `emptyDir` volumes, `shutdownPolicy: Delete` |
| PVCs should die with Sandbox | `volumeClaimTemplates` (cascade on delete) |
| PVCs must survive Sandbox deletion (RECOMMENDED for raw Sandbox) | Standalone PVCs in `podTemplate.spec.volumes` |
| Repeated runs with same data (CronJob pattern) | Standalone PVCs (no ownership cascade) |
| SandboxTemplate + SandboxClaim pattern | `volumeClaimTemplates` in template (each claim gets fresh PVCs) |

```yaml
# RECOMMENDED for raw Sandbox reuse: standalone PVCs (survive Sandbox deletion)
spec:
  podTemplate:
    spec:
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: my-workspace-pvc    # created separately
      containers:
        - name: main
          volumeMounts:
            - name: workspace
              mountPath: /workspace

# For SandboxTemplate pattern: volumeClaimTemplates (each claim gets own PVCs)
spec:
  volumeClaimTemplates:
    - metadata: { name: workspace }
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
```

### Ownership hierarchy with KRO (raw Sandbox)

When using KRO to manage raw Sandboxes, the ideal ownership chain is:

```
KRO Custom Resource (e.g., ClaudeCodeAgentSandbox)
  ├── owns → PVCs (workspace + memory)       ← siblings of Sandbox
  ├── owns → ConfigMap
  ├── owns → Sandbox CR                       ← does NOT own PVCs
  └── owns → CronJob (if schedule)
```

This means:
- Deleting the **Sandbox** alone → PVCs survive (they're siblings, not children)
- Deleting the **KRO CR** → everything cleaned up (KRO manages all)
- Sandbox can be deleted/recreated (e.g., to re-run) without data loss

### Pod Lifecycle and Container Exit

When a container exits with `restartPolicy: Never`:

1. Pod enters `Succeeded` (exit 0) or `Failed` (non-zero) phase
2. Controller sets status conditions:
   - `Finished=True` with reason `PodSucceeded` or `PodFailed`
   - `Ready=False` with reason `SandboxExpired`
3. Pod and Service are deleted by the controller
4. Sandbox CR behavior depends on `shutdownPolicy`:
   - `Retain`: CR stays with status conditions (PVCs stay)
   - `Delete`: CR is auto-deleted (PVCs cascade-deleted)

### Status Conditions

```yaml
status:
  conditions:
    - type: Ready
      status: "True"       # Pod running and ready
    - type: Finished
      status: "True"       # Pod reached terminal phase
      reason: PodSucceeded # or PodFailed
  podIPs: ["10.244.0.5"]
  replicas: 1
  service: my-sandbox
  serviceFQDN: my-sandbox.default.svc.cluster.local
```

### Waiting for Sandbox Completion

```bash
kubectl wait --for=condition=Finished sandbox/<name> -n <namespace> --timeout=180s
kubectl get sandbox <name> -n <namespace> -o jsonpath='{.status.conditions}'
```

---

## Extension CRDs

API Group: `extensions.agents.x-k8s.io/v1alpha1`
Installed with the same manifest as the core controller.

### SandboxTemplate

Reusable blueprint for creating sandboxes with consistent configuration, NetworkPolicy, and env injection policies.

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxTemplate
metadata:
  name: my-agent-template
  namespace: default
spec:
  # REQUIRED — pod definition (same as Sandbox.spec.podTemplate)
  podTemplate:
    metadata:
      labels:
        app: my-agent
    spec:
      restartPolicy: Never
      containers:
        - name: agent
          image: my-agent:latest
          ports:
            - containerPort: 8888
      initContainers:
        - name: sidecar
          image: sidecar:latest
          restartPolicy: Always

  # OPTIONAL — PVC templates (each SandboxClaim gets its own PVCs)
  volumeClaimTemplates:
    - metadata:
        name: workspace
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi

  # OPTIONAL — NetworkPolicy management
  networkPolicyManagement: Managed      # Managed (default) or Unmanaged
  networkPolicy:                        # Custom rules (omit for secure defaults)
    ingress: [...]
    egress: [...]

  # OPTIONAL — env var injection from SandboxClaim
  envVarsInjectionPolicy: Disallowed    # Disallowed (default), Allowed, or Overrides

  # OPTIONAL — headless Service for sandboxes
  service: true
```

#### NetworkPolicy Management

When `networkPolicyManagement: Managed` (default), the controller creates a single shared `NetworkPolicy` named `<template-name>-network-policy` in the template's namespace.

**Secure-by-Default posture** (when no custom `networkPolicy` rules are specified):

| Direction | Traffic | Status |
|-----------|---------|--------|
| Ingress | From Sandbox Router (`app: sandbox-router`) | Allowed |
| Ingress | All other cluster/external traffic | Blocked |
| Egress | Public Internet (`0.0.0.0/0`, `::/0`) | Allowed |
| Egress | RFC1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) | Blocked |
| Egress | Metadata Server (`169.254.0.0/16`) | Blocked |
| Egress | IPv6 ULAs (`fc00::/7`) | Blocked |
| Egress | Internal Cluster DNS | Blocked |

DNS is overridden to use public resolvers (Google/Cloudflare) unless `dnsPolicy: ClusterFirst` is explicitly set.

**Custom rules** completely replace secure defaults:

```yaml
# Air-gapped (no network at all)
spec:
  networkPolicyManagement: Managed
  networkPolicy:
    ingress: []
    egress: []

# Allow specific internal DB + public internet
spec:
  networkPolicyManagement: Managed
  networkPolicy:
    ingress:
      - from:
        - podSelector:
            matchLabels:
              app: sandbox-router
    egress:
      - to:
        - ipBlock:
            cidr: 10.10.10.100/32
        ports:
          - protocol: TCP
            port: 5432
      - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
              - 169.254.0.0/16
```

**Unmanaged mode** — set `networkPolicyManagement: Unmanaged` to defer to external systems (Cilium, Istio). Target pods via label `agents.x-k8s.io/sandbox-template-ref-hash`.

#### Env Vars Injection Policy

Controls whether SandboxClaim can inject environment variables:

| Policy | Behavior |
|--------|----------|
| `Disallowed` (default) | Claim rejected if it specifies env vars |
| `Allowed` | Claim can inject new env vars, cannot override template-defined ones |
| `Overrides` | Claim can inject new and override existing env vars |

Use `Overrides` when the template defines env vars (like `TARGET_REPO`) that each claim needs to customize per-run.

---

### SandboxClaim

High-level abstraction that references a template and creates/adopts a sandbox. Like PVC→PV binding.

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxClaim
metadata:
  name: my-agent-run
  namespace: default
spec:
  # REQUIRED — which template to use
  sandboxTemplateRef:
    name: my-agent-template

  # OPTIONAL — warm pool adoption policy
  warmpool: default                    # "none", "default", or "<pool-name>"

  # OPTIONAL — lifecycle management
  lifecycle:
    shutdownTime: "2025-12-31T23:59:59Z"   # absolute expiry
    ttlSecondsAfterFinished: 300            # auto-delete N seconds after Finished
    shutdownPolicy: Delete                  # Delete, DeleteForeground, or Retain (default)

  # OPTIONAL — extra labels/annotations propagated to sandbox pod
  additionalPodMetadata:
    labels:
      run-id: "abc123"

  # OPTIONAL — env vars (requires template envVarsInjectionPolicy: Allowed or Overrides)
  env:
    - name: TARGET_REPO
      value: "owner/repo"
    - name: AGENT_TASK
      value: "Fix the login bug"
    - name: MY_VAR
      value: "value"
      containerName: specific-container   # default: first container
```

#### Warm Pool Policies

| Policy | Behavior |
|--------|----------|
| `none` | Always create fresh sandbox (no pool adoption) |
| `default` (default) | Select from all matching warm pools |
| `<pool-name>` | Select only from the specified warm pool |

#### Shutdown Policies

| Policy | Behavior |
|--------|----------|
| `Retain` (default) | Claim stays, underlying sandbox resources deleted on expiry |
| `Delete` | Claim and sandbox deleted on expiry |
| `DeleteForeground` | Foreground cascade — claim lingers until pod terminates |

#### Status

```yaml
status:
  conditions:
    - type: Finished
      status: "True"
      reason: PodSucceeded
  sandbox:
    name: my-agent-run-xyz     # adopted sandbox name
    podIPs: ["10.244.0.5"]
```

---

### SandboxWarmPool

Pre-warmed pool of idle sandboxes ready for instant allocation to SandboxClaims.

```yaml
apiVersion: extensions.agents.x-k8s.io/v1alpha1
kind: SandboxWarmPool
metadata:
  name: my-agent-pool
  namespace: default
spec:
  # REQUIRED — desired pool size
  replicas: 5

  # REQUIRED — template to use
  sandboxTemplateRef:
    name: my-agent-template

  # OPTIONAL — update strategy
  updateStrategy:
    type: OnReplenish          # OnReplenish (default) or Recreate
```

#### Update Strategies

| Strategy | Behavior |
|----------|----------|
| `OnReplenish` (default) | Stale pods replaced only when adopted by claims or manually deleted |
| `Recreate` | Stale pods deleted immediately when template PodSpec changes |

#### HPA Compatibility

SandboxWarmPool exposes a scale subresource — you can attach an HPA to dynamically scale the pool based on custom metrics (e.g., claim creation rate).

#### Status

```yaml
status:
  replicas: 5         # total sandboxes in pool
  readyReplicas: 4    # ready sandboxes
  selector: "..."     # pod label selector
```

---

## Sandbox Router

Lightweight async reverse proxy (FastAPI/Uvicorn) that routes requests to sandboxes by `X-Sandbox-ID` header. Required for the secure-by-default NetworkPolicy (ingress allows only `app: sandbox-router`).

Request flow:
1. Client sends request with `X-Sandbox-ID: <sandbox-name>` header
2. Router constructs target: `<sandbox-id>.<namespace>.svc.cluster.local:<port>`
3. Proxies request to sandbox's headless Service
4. Streams response back

Headers:
- `X-Sandbox-ID` (required) — sandbox name
- `X-Sandbox-Namespace` (optional, default: `default`)
- `X-Sandbox-Port` (optional, default: `8888`)
- `X-Sandbox-Pod-IP` (optional) — route by IP instead of DNS

---

## Python SDK

Package: `k8s-agent-sandbox` (pip install)

### Connection Modes

| Mode | Class | Use Case |
|------|-------|----------|
| Tunnel (default) | `SandboxLocalTunnelConnectionConfig` | Dev: uses `kubectl port-forward` |
| Gateway | `SandboxGatewayConnectionConfig` | Prod: public Kubernetes Gateway |
| Direct | `SandboxDirectConnectionConfig` | In-cluster agents or custom domains |

### Usage

```python
from k8s_agent_sandbox import SandboxClient

client = SandboxClient()

# Create sandbox from template (adopts from warm pool if available)
sandbox = client.create_sandbox(
    template="my-agent-template",
    namespace="default",
    warmpool="default",                # optional: warm pool policy
    shutdown_after_seconds=3600,       # optional: auto-delete after 1h
)

try:
    # Execute commands
    result = sandbox.commands.run("echo 'Hello from sandbox!'")
    print(result.stdout)

    # File operations
    sandbox.files.write("hello.py", 'print("Hello")\n')
    result = sandbox.commands.run("python3 hello.py")
    print(result.stdout)
finally:
    sandbox.terminate()

# Retrieve existing sandbox
sandbox = client.get_sandbox("sandbox-claim-abc123", namespace="default")

# Cleanup all tracked sandboxes
client.delete_all()
```

### Async Support

```python
from k8s_agent_sandbox import AsyncSandboxClient  # requires pip install k8s-agent-sandbox[async]
```

---

## Two-RGD Architecture (Concept 07 — Raw Sandbox)

Two RGDs work together: `ClaudeCodeAgentSandboxRunner` (internal) and `ClaudeCodeAgentSandbox` (user-facing).

### Mode 1: Standalone (no schedule)

```
ClaudeCodeAgentSandbox CR
  ├── owns → PVC (workspace)
  ├── owns → PVC (memory)
  ├── owns → ConfigMap (entrypoint + prompt)
  └── owns → ClaudeCodeAgentSandboxRunner CR
               └── owns → Sandbox CR (full Bash inside)
```

### Mode 2: CronJob Orchestrator (with schedule)

```
ClaudeCodeAgentSandbox CR
  ├── owns → PVC (workspace)
  ├── owns → PVC (memory)
  ├── owns → ConfigMap (entrypoint + orchestrator + prompt)
  ├── owns → ServiceAccount + Role + RoleBinding
  └── owns → CronJob
               └── CronJob pod (bitnami/kubectl) runs:
                     kubectl create Runner → wait for Sandbox Finished → stream logs → delete Runner
```

### Key Design Decisions

- **Claude ALWAYS runs inside a Sandbox** — full Bash, no MCP routing needed
- **PVCs are siblings** — owned by parent CR, survive Runner deletion
- **Runner takes PVC names as input** — mounts existing PVCs, doesn't create them
- **CronJob image**: `bitnami/kubectl:latest` (minimal: kubectl + bash only)

---

## SandboxTemplate Architecture (Concept 08 — Extension CRDs)

Simpler pattern using Extension CRDs. No custom Runner RGD needed.

### Mode 1: One-shot (no schedule)

```
ClaudeCodeAgentTemplate CR (KRO)
  ├── owns → SandboxTemplate (pod spec + NetworkPolicy)
  ├── owns → SandboxWarmPool (pre-warms N sandboxes)
  ├── owns → ConfigMap (entrypoint + prompt)
  ├── owns → ConfigMap (proxy config)
  └── owns → SandboxClaim (one-shot execution, adopts from warm pool)
```

### Mode 2: CronJob (with schedule)

```
ClaudeCodeAgentTemplate CR (KRO)
  ├── owns → SandboxTemplate (pod spec + NetworkPolicy)
  ├── owns → SandboxWarmPool (pre-warms N sandboxes)
  ├── owns → ConfigMap (entrypoint + prompt)
  ├── owns → ConfigMap (proxy config)
  ├── owns → ServiceAccount + Role + RoleBinding
  └── owns → CronJob
               └── CronJob pod creates SandboxClaim → waits → claim auto-deletes via TTL
```

### Key Differences from Concept 07

| Aspect | 07 (Raw Sandbox) | 08 (Extension CRDs) |
|--------|-------------------|----------------------|
| CRDs used | Sandbox only | SandboxTemplate + SandboxClaim + SandboxWarmPool |
| NetworkPolicy | Manual (or none) | Managed, secure-by-default |
| Warm pool | Not available | Built-in fast-start |
| PVC lifecycle | Manual (siblings via KRO) | Template-owned (each claim gets fresh PVCs) |
| Orchestration | kubectl Runner management | SandboxClaim with TTL auto-cleanup |
| Env vars per-run | Baked into Runner spec | Injected via SandboxClaim.env |

---

## GKE Pod Snapshots (Hibernation/Resume)

**GKE-only extension** — NOT available on Kind or generic Kubernetes.

Requires: GKE Standard + gVisor + Pod Snapshot Controller + GCS bucket

| Operation | What happens |
|-----------|-------------|
| **Suspend** | Snapshot process memory → scale to 0 (no compute cost) |
| **Resume** | Scale to 1 → restore from snapshot (process continues mid-execution) |

For Kind/generic K8s, use Claude's `--continue` flag with PVC-backed `.claude/` directory instead.

---

## RuntimeClass for gVisor

Linux-only. Requires `runsc` installed on nodes + a RuntimeClass:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

Then set `podTemplate.spec.runtimeClassName: gvisor`. Does NOT work on macOS/Kind.

---

## Installation

```bash
export VERSION="v0.4.6"
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/manifest.yaml
kubectl wait --for=condition=Available deploy -n agent-sandbox-system --all --timeout=60s
```

This installs both core (Sandbox) and extension (SandboxTemplate, SandboxClaim, SandboxWarmPool) controllers.

---

## Labels and Annotations Applied by Controllers

| Label/Annotation | Location | Purpose |
|------------------|----------|---------|
| `agents.x-k8s.io/sandbox-name-hash` | Pod | Primary pod selector |
| `agents.x-k8s.io/sandbox-name` | Pod | Sandbox name |
| `agents.x-k8s.io/sandbox-template-ref-hash` | Pod | Template ref hash (NetworkPolicy targeting) |
| `agents.x-k8s.io/sandbox-pod-template-hash` | Pod | Pod template hash (update detection) |
| `agents.x-k8s.io/claim-uid` | Pod | Owning claim UID |
| `agents.x-k8s.io/sandbox-name` | SandboxClaim | Assigned sandbox name |
| `agents.x-k8s.io/sandbox-template-ref` | Sandbox (annotation) | Template reference |
| `agents.x-k8s.io/pod-name` | Sandbox (annotation) | Adopted pod name |
