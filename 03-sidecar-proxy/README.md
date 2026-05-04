# 03 - Sidecar Proxy for Credential Security

Secure API credentials by keeping them out of the application container. A sidecar proxy intercepts outbound API calls and injects the real credentials — for both Anthropic and GitHub.

## Concept

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Pod                                                   │
│                                                                  │
│  ┌────────────────────────────┐  ┌───────────────────────────┐  │
│  │ claude-code container      │  │ proxy sidecar (port 8080) │  │
│  │                            │  │                           │  │
│  │ ANTHROPIC_API_KEY=FAKE     │  │ Has REAL credentials:     │  │
│  │ GH_TOKEN=FAKE              │  │ ANTHROPIC_API_KEY=sk-ant… │  │
│  │                            │  │ GH_TOKEN=ghp_…            │  │
│  │ ANTHROPIC_BASE_URL=        │  │                           │  │
│  │   http://localhost:8080    │  │ Mode 1: Plain HTTP        │  │
│  │ HTTPS_PROXY=               │  │   → Anthropic API         │  │
│  │   http://localhost:8080    │  │   (inject x-api-key)      │  │
│  │ NO_PROXY=localhost         │  │                           │  │
│  │                            │  │ Mode 2: CONNECT + MITM    │  │
│  │ Trusts proxy CA cert       │  │   → github.com            │  │
│  │ from /certs/proxy-ca.crt   │  │   → api.github.com        │  │
│  └────────────────────────────┘  │   (replace Authorization) │  │
│                                  └───────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Traffic Flows

1. **Claude SDK → Anthropic API** (plain HTTP reverse proxy):
   - SDK reads `ANTHROPIC_BASE_URL=http://localhost:8080`
   - Sends plain HTTP to proxy → proxy injects `x-api-key` → forwards to `https://api.anthropic.com`
   - `NO_PROXY=localhost` prevents `HTTPS_PROXY` from applying here

2. **`gh` CLI → GitHub API** (HTTPS CONNECT + MITM):
   - `HTTPS_PROXY=http://localhost:8080` → gh sends `CONNECT api.github.com:443`
   - Proxy terminates TLS with ephemeral cert signed by proxy CA
   - Reads `Authorization: token FAKE…` → replaces with real token → forwards to upstream

3. **`git` → GitHub** (HTTPS CONNECT + MITM):
   - Same HTTPS_PROXY flow → `CONNECT github.com:443`
   - Proxy replaces Basic auth password with real token → forwards to upstream

## Why This Matters

In concept 02, credentials are directly available as environment variables. This means:
- Anyone with `kubectl exec` access can read them
- They appear in `kubectl describe pod` output
- They can leak into logs if the application prints env vars
- Container runtime inspection reveals them

With the sidecar proxy pattern:
- The main container only has fake/sentinel values for ALL credentials
- Real keys exist only in the sidecar container's memory
- The sidecar is a minimal, auditable component
- CONNECT requests are allowlisted (only `github.com` and `api.github.com`)

### Ephemeral Certificate Lifecycle

1. Sidecar starts first (native K8s sidecar via `restartPolicy: Always`)
2. `entrypoint.sh` generates a CA + server cert with `openssl` (1-day validity)
3. CA cert is written to a shared `emptyDir` volume at `/certs/proxy-ca.crt`
4. Main container starts, trusts the CA via `SSL_CERT_FILE` / `GIT_SSL_CAINFO` / `NODE_EXTRA_CA_CERTS`
5. Certs are ephemeral — fresh per pod, nothing baked into images or committed to the repo

## Reference Projects

- [agentsecrets](https://github.com/The-17/agentsecrets) — Proxy that replaces sentinel values with real credentials
- [wardgate](https://github.com/wardgate/wardgate) — Gateway for securing AI agent credentials

## Prerequisites

- Kind cluster running (see [01-kind-cluster](../01-kind-cluster/))
- Claude Code image loaded (see [02-claude-k8s-job](../02-claude-k8s-job/))
- `.env` file with `ANTHROPIC_API_KEY` set (and optionally `GH_TOKEN`)

## Step-by-Step

### 1. Build the proxy image

```bash
docker build -t credential-proxy:latest proxy/
kind load docker-image credential-proxy:latest --name claude-demo
```

### 2. Create the Secret (real keys for sidecar only)

```bash
kubectl create secret generic agent-credentials \
  --from-env-file=../../.env \
  -n 03-sidecar-proxy
```

### 3. Run the Job

```bash
kubectl apply -f manifests/job.yaml
```

### 4. Watch the output

```bash
kubectl logs -f job/claude-hello-secure -c claude-code -n 03-sidecar-proxy
```

## How to Verify

Exec into the main container and check the environment — you should only see fake values:

```bash
kubectl exec job/claude-hello-secure -c claude-code -n 03-sidecar-proxy -- env | grep -E 'ANTHROPIC_API_KEY|GH_TOKEN'
```

Expected:
```
ANTHROPIC_API_KEY=FAKE_KEY_REPLACED_BY_PROXY
GH_TOKEN=FAKE_GH_TOKEN_REPLACED_BY_PROXY
```

The real keys only exist in the sidecar:
```bash
kubectl exec job/claude-hello-secure -c proxy-sidecar -n 03-sidecar-proxy -- env | grep -E 'ANTHROPIC|GH_TOKEN'
```

## Expected Output

Claude Code should work normally (the proxy transparently injects the real key), but the main container never has access to real credentials.

## Cleanup

```bash
kubectl delete -f manifests/job.yaml
kubectl delete secret agent-credentials -n 03-sidecar-proxy
```
