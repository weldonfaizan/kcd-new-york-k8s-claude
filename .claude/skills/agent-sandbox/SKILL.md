---
name: agent-sandbox
description: Write Sandbox CRDs for kubernetes-sigs/agent-sandbox. Use when creating Sandbox resources, volumeClaimTemplates, or integrating Sandbox with KRO RGDs.
allowed-tools: Read, Grep, Glob
---

# Agent Sandbox CRD Reference

API Group: `agents.x-k8s.io/v1alpha1`
Kind: `Sandbox`
Scope: Namespaced
Version: v0.4.3

## Sandbox Spec — All Fields

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
```

## volumeClaimTemplates

### Naming

PVC name = `{vct.metadata.name}-{sandbox.metadata.name}`

Example: VCT `workspace` + Sandbox `claude-dev-sandbox` → PVC `workspace-claude-dev-sandbox`

### Volume Injection

The controller automatically injects a volume with the VCT's short name (`workspace`) into the pod, pointing to the generated PVC. You only need to define `volumeMounts` in your containers — no need to define matching `volumes` in `podTemplate.spec.volumes`.

### Ownership and Lifecycle (CRITICAL)

PVCs created from `volumeClaimTemplates` are **owned by the Sandbox CR** via `ownerReference` with `controller: true`. This has important implications:

| Action | PVC Behavior |
|--------|-------------|
| Container exits, Sandbox CR stays (`shutdownPolicy: Retain`) | PVCs **stay** (owner still exists) |
| Sandbox CR deleted (any reason) | PVCs **cascade-deleted** by Kubernetes GC |
| `kubectl delete sandbox X --cascade=orphan` | PVCs **orphaned** (survive, ownerRef removed) |
| New Sandbox created, finds orphaned PVC | PVC **re-adopted** (ownerRef added back) |

**Key insight**: You CANNOT delete and recreate a Sandbox to reuse PVCs in normal flow. Deleting the Sandbox cascades to PVCs. Use one of these patterns instead:

1. **Keep Sandbox alive** — with `shutdownPolicy: Retain`, the Sandbox CR stays after container exit. PVCs persist. (But you can't re-run the container without deleting/recreating.)
2. **Orphan delete** — `kubectl delete sandbox X --cascade=orphan` then recreate with same name. Controller finds unowned PVCs and re-adopts them.
3. **Standalone PVCs** — create PVCs independently (not via volumeClaimTemplates), mount them via `podTemplate.spec.volumes`. No ownership cascade.

### When to use volumeClaimTemplates vs standalone PVCs

| Use Case | Approach |
|----------|----------|
| Ephemeral sandbox (no persistence needed) | `emptyDir` volumes, `shutdownPolicy: Delete` |
| PVCs should die with Sandbox | `volumeClaimTemplates` (cascade on delete) |
| PVCs must survive Sandbox deletion (RECOMMENDED) | Standalone PVCs in `podTemplate.spec.volumes` |
| Repeated runs with same data (CronJob pattern) | Standalone PVCs (no ownership cascade) |

**Best practice**: Use standalone PVCs mounted via `podTemplate.spec.volumes`. This decouples PVC lifecycle from the Sandbox CR, allowing you to delete/recreate the Sandbox without losing data. The PVCs are owned by a parent resource (e.g., KRO CR) or managed independently.

```yaml
# RECOMMENDED: standalone PVCs in pod spec (survive Sandbox deletion)
spec:
  podTemplate:
    spec:
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: my-workspace-pvc    # created separately
        - name: claude-memory
          persistentVolumeClaim:
            claimName: my-memory-pvc       # created separately
      containers:
        - name: main
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: claude-memory
              mountPath: /home/claude/.claude

# NOT RECOMMENDED for reuse: volumeClaimTemplates (cascade-deleted with Sandbox)
spec:
  volumeClaimTemplates:
    - metadata: { name: workspace }
      spec: { ... }
```

### Ownership hierarchy with KRO

When using KRO to manage Sandboxes, the ideal ownership chain is:

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

## Pod Lifecycle and Container Exit

When a container exits with `restartPolicy: Never`:

1. Pod enters `Succeeded` (exit 0) or `Failed` (non-zero) phase
2. Controller sets status conditions:
   - `Finished=True` with reason `PodSucceeded` or `PodFailed`
   - `Ready=False` with reason `SandboxExpired`
3. Pod and Service are deleted by the controller
4. Sandbox CR behavior depends on `shutdownPolicy`:
   - `Retain`: CR stays with status conditions (PVCs stay)
   - `Delete`: CR is auto-deleted (PVCs cascade-deleted)

```
Container running → exits → Pod phase=Succeeded
  → Controller detects Finished condition
  → Deletes Pod
  → Deletes Service
  → shutdownPolicy: Retain → Sandbox CR stays, PVCs stay
  → shutdownPolicy: Delete → Sandbox CR deleted → PVCs cascade-deleted
```

## Status Conditions

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

## Labels Applied by Controller

- `agents.x-k8s.io/sandbox-name-hash: <hash>` — primary label on pod
- `agents.x-k8s.io/sandbox-name: <name>` — sandbox name label
- A headless Service is created automatically: `{sandbox-name}.{namespace}.svc.cluster.local`

## Waiting for Sandbox Completion

```bash
# Wait for pod to finish (no Job, direct pod)
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/<sandbox-name> -n <namespace> --timeout=180s

# Check sandbox status
kubectl get sandbox <name> -n <namespace> -o jsonpath='{.status.conditions}'
```

## Two-RGD Architecture (Concept 07)

Two RGDs work together: `ClaudeCodeAgentSandboxRunner` (internal) and `ClaudeCodeAgentSandbox` (user-facing).

### Mode 1: Standalone (no schedule)

The parent CR creates a Runner directly. The Runner creates a Sandbox with full Bash access.

```
ClaudeCodeAgentSandbox CR
  ├── owns → PVC (workspace)
  ├── owns → PVC (memory)
  ├── owns → ConfigMap (entrypoint + prompt)
  └── owns → ClaudeCodeAgentSandboxRunner CR
               └── owns → Sandbox CR (full Bash inside)
```

### Mode 2: CronJob Orchestrator (with schedule)

The parent CR creates RBAC + CronJob. The CronJob pod uses `kubectl` to create a Runner, wait for it, stream logs, then delete it.

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
- **Runner naming**: `${PARENT_NAME}-run-$(date +%s)` for uniqueness per CronJob run
- **No ownerRef hack** — CronJob creates/deletes Runners explicitly

## GKE Pod Snapshots (Hibernation/Resume)

**GKE-only extension** — NOT available on Kind or generic Kubernetes.

Requires: GKE Standard + gVisor + Pod Snapshot Controller + GCS bucket

| Operation | What happens |
|-----------|-------------|
| **Suspend** | Snapshot process memory → scale to 0 (no compute cost) |
| **Resume** | Scale to 1 → restore from snapshot (process continues mid-execution) |

This is full process hibernation (memory, file descriptors), not just file persistence. For Kind/generic K8s, use Claude's `--continue` flag with PVC-backed `.claude/` directory instead.

## RuntimeClass for gVisor

Linux-only. Requires `runsc` installed on nodes + a RuntimeClass:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

Then set `podTemplate.spec.runtimeClassName: gvisor` in the Sandbox.

Does NOT work on macOS/Kind — omit `runtimeClassName` for local development.

## Extension CRDs

Installed separately. Group: `extensions.agents.x-k8s.io/v1alpha1`.

| Kind | Purpose |
|------|---------|
| `SandboxTemplate` | Reusable template with NetworkPolicy and env injection policies |
| `SandboxClaim` | Request a Sandbox from a template (like PVC→PV) |
| `SandboxWarmPool` | Pre-warmed pool of Sandboxes for instant allocation |

## Installation

```bash
export VERSION="v0.4.3"
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/manifest.yaml
kubectl wait --for=condition=Available deploy -n agent-sandbox-system --all --timeout=60s
```
