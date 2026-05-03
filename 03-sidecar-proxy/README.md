# 03 - Sidecar Proxy for Credential Security

Secure API credentials by keeping them out of the application container. A sidecar proxy intercepts outbound API calls and injects the real credentials.

## Concept

```
┌──────────────────────────────────────────────────────┐
│ Kubernetes Pod                                       │
│                                                      │
│  ┌──────────────────────┐   ┌─────────────────────┐ │
│  │ claude-code container │   │ proxy sidecar       │ │
│  │                       │   │                     │ │
│  │ ANTHROPIC_API_KEY=    │   │ ANTHROPIC_API_KEY=  │ │
│  │   FAKE_KEY_REPLACED   │   │   sk-ant-real...   │ │
│  │                       │   │                     │ │
│  │ ANTHROPIC_BASE_URL=   │   │ Listens on :8080   │ │
│  │   http://localhost:   │   │ Forwards to:       │ │
│  │   8080                │   │   api.anthropic.com │ │
│  └───────────┬───────────┘   └──────────┬──────────┘ │
│              │ HTTP request              │            │
│              └──────────────────────────►│            │
│                                          │            │
└──────────────────────────────────────────┼────────────┘
                                           │
                                           ▼
                                   api.anthropic.com
                                   (with real API key)
```

## Why This Matters

In concept 02, the API key is directly available as an environment variable. This means:
- Anyone with `kubectl exec` access can read it
- It appears in `kubectl describe pod` output
- It can leak into logs if the application prints env vars
- Container runtime inspection reveals it

With the sidecar proxy pattern:
- The main container only has a fake/sentinel key
- The real key exists only in the sidecar container's memory
- The sidecar is a minimal, auditable component

## Reference Projects

- [agentsecrets](https://github.com/The-17/agentsecrets) — Proxy that replaces sentinel values with real credentials
- [wardgate](https://github.com/wardgate/wardgate) — Gateway for securing AI agent credentials

## Prerequisites

- Kind cluster running (see [01-kind-cluster](../01-kind-cluster/))
- Claude Code image loaded (see [02-claude-k8s-job](../02-claude-k8s-job/))
- `.env` file with `ANTHROPIC_API_KEY` set

## Step-by-Step

### 1. Build the proxy image

```bash
docker build -t credential-proxy:latest proxy/
kind load docker-image credential-proxy:latest --name claude-demo
```

### 2. Create the Secret (real key for sidecar only)

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
kubectl logs -f job/claude-hello-secure -c claude-code -n claude-demo
```

## How to Verify

Exec into the main container and check the environment — you should only see the fake key:

```bash
kubectl exec job/claude-hello-secure -c claude-code -n claude-demo -- env | grep ANTHROPIC
```

Expected:
```
ANTHROPIC_API_KEY=FAKE_KEY_REPLACED_BY_PROXY
ANTHROPIC_BASE_URL=http://localhost:8080
```

The real key only exists in the sidecar:
```bash
kubectl exec job/claude-hello-secure -c proxy-sidecar -n claude-demo -- env | grep ANTHROPIC
```

## Expected Output

Claude Code should work normally (the proxy transparently injects the real key), but the main container never has access to the real credential.

## Cleanup

```bash
kubectl delete -f manifests/job.yaml
kubectl delete secret anthropic-credentials -n claude-demo
```
