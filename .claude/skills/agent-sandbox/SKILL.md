---
name: agent-sandbox
description: Write Sandbox CRDs for kubernetes-sigs/agent-sandbox. Use when creating Sandbox resources, volumeClaimTemplates, or integrating Sandbox with KRO RGDs.
allowed-tools: Read, Grep, Glob
---

# Agent Sandbox CRD Reference

API Group: `agents.x-k8s.io/v1alpha1`
Kind: `Sandbox`
Scope: Namespaced

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

  # OPTIONAL — PVC templates
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

## volumeClaimTemplates Naming

PVC name = `{vct.metadata.name}-{sandbox.metadata.name}`

Example: VCT `workspace` + Sandbox `claude-dev-sandbox` → PVC `workspace-claude-dev-sandbox`

The controller automatically injects a volume with the VCT's short name (`workspace`) into the pod, pointing to the generated PVC. You only need to define `volumeMounts` in your containers — no need to define matching `volumes` in `podTemplate.spec.volumes`.

## Pod Lifecycle

- `restartPolicy: Never` → pod exits → Sandbox condition `Finished=True`
- Controller does NOT restart the pod. To re-run: delete and recreate the Sandbox.
- `replicas: 0` deletes the pod but keeps PVCs (pause). `replicas: 1` recreates it (resume).

## Labels Applied by Controller

- `agents.x-k8s.io/sandbox-name-hash: <hash>` — primary selector on pod
- A headless Service is created automatically: `{sandbox-name}.{namespace}.svc.cluster.local`

## MCP-Based Sandbox Integration Pattern

In concept 07, the Sandbox is used as a remote command execution environment. Claude Code's Bash tool is disabled and replaced by an MCP server that forwards commands to the Sandbox pod's HTTP API.

Key components:
- **`--disallowedTools Bash`** — removes the built-in Bash tool from Claude Code
- **MCP server** (FastMCP, stdio transport) — provides `sandbox_execute` tool
- **Sandbox HTTP API** — Python `http.server` accepting POST /execute
- **Shared workspace PVC** — mounted in both Job and Sandbox pods for filesystem coherence

```yaml
# KRO resource generating a Sandbox for command execution
- id: agentSandbox
  template:
    apiVersion: agents.x-k8s.io/v1alpha1
    kind: Sandbox
    metadata:
      name: ${schema.metadata.name}-sandbox
      namespace: ${schema.metadata.namespace}
    spec:
      volumeClaimTemplates:
        - metadata:
            name: workspace
          spec:
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 5Gi
      podTemplate:
        spec:
          restartPolicy: Never
          containers:
            - name: sandbox-runtime
              image: claude-code:latest
              command: ["/bin/bash", "/scripts/sandbox-entrypoint.sh"]
              env:
                - name: GH_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: ${schema.spec.credentials.secretName}
                      key: GH_TOKEN
              volumeMounts:
                - name: workspace
                  mountPath: /workspace
              ports:
                - containerPort: 8080
```

The Job pod references the Sandbox's workspace PVC by naming convention:

```yaml
volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: workspace-${agentSandbox.metadata.name}
```

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
