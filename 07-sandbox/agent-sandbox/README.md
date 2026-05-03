# Concept 07: Agent Sandbox Isolation

Run Claude Code agents with **isolated command execution** — the agent's Bash tool is replaced by an MCP server that **routes commands**: git/gh run locally (for speed and credential access), while everything else (npm, node, python, go) runs in a separate [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) pod. Files are automatically synced between local and sandbox using the SDK-compatible filesystem API.

## What You Learn

- How `--disallowedTools Bash` removes the Bash tool from Claude Code
- How an MCP server (FastMCP, stdio) provides a `sandbox_execute` tool with smart routing
- How the agent-sandbox Python SDK's filesystem APIs (upload, download, list, exists) enable file sync
- How `kubernetes-sigs/agent-sandbox` provides lifecycle-managed sandbox pods with stable DNS
- How the RGD's `allowedLocalCommands` field lets platform teams control what runs locally vs. in sandbox

## Architecture

```
ClaudeCodeAgentSandbox CR
        │
        ├── ConfigMap (entrypoint, prompt, MCP server, sandbox runtime)
        ├── PVC (claude-memory)
        ├── Sandbox (isolated execution pod + workspace PVC)
        └── Job (Claude Code CLI, git/gh local, rest → sandbox)
```

The MCP server checks each command against a whitelist:
- **`git`, `gh`** (configurable) → run locally in the Job pod
- **Everything else** → sync workspace to sandbox, execute via HTTP, sync results back

The sandbox runtime implements the same API as the official `python-runtime-sandbox` from kubernetes-sigs/agent-sandbox, making it compatible with the Python SDK's `CommandExecutor` and `Filesystem` classes.

## Prerequisites

- Completed concepts [01](../../01-kind-cluster/) through [06](../../06-kro-agent/)
- Kind cluster running with KRO installed
- `claude-code:latest` and `credential-proxy:latest` images loaded into Kind

## Step-by-Step

### 1. Rebuild the Claude Code image

Concept 07 requires additional Python packages (FastMCP, FastAPI, uvicorn, requests):

```bash
cd 02-claude-k8s-job
docker build -t claude-code:latest .
kind load docker-image claude-code:latest --name claude-demo
cd ..
```

### 2. Install agent-sandbox controller

```bash
export VERSION="v0.4.3"
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/manifest.yaml
kubectl wait --for=condition=Available deploy -n agent-sandbox-system --all --timeout=60s
```

Verify:

```bash
kubectl get crd sandboxes.agents.x-k8s.io
```

### 3. Apply the RGD

```bash
kubectl apply -f 07-sandbox/agent-sandbox/manifests/rgd.yaml
```

Verify the CRD was created:

```bash
kubectl get crd claudecodeagentsandboxes.kro.run
```

### 4. Deploy the developer agent

```bash
set -a && source .env && set +a
envsubst '$TESTING_REPO' < 07-sandbox/agent-sandbox/manifests/developer-instance.yaml | kubectl apply -f -
```

### 5. Verify resources

```bash
kubectl get claudecodeagentsandbox,sandbox,configmap,pvc,job,pod -n claude-demo
```

You should see:
- A `ClaudeCodeAgentSandbox` CR
- A `Sandbox` CR (`claude-developer-sandbox`)
- A ConfigMap (`claude-developer-config`)
- Two PVCs (`workspace-claude-developer-sandbox` and `claude-developer-memory`)
- A Job (`claude-developer`)
- Two pods (sandbox runtime + job pod with proxy sidecar)

### 6. Verify sandbox isolation

Check that the Job pod has fake credentials:

```bash
JOB_POD=$(kubectl get pod -n claude-demo -l job-name=claude-developer -o name)
kubectl exec $JOB_POD -c claude-code -n claude-demo -- env | grep -E 'API_KEY|GH_TOKEN'
```

Expected: `FAKE_KEY_REPLACED_BY_PROXY` and `FAKE_GH_TOKEN_REPLACED_BY_PROXY`

Check the sandbox is serving the SDK-compatible API:

```bash
SANDBOX_POD=$(kubectl get pod -n claude-demo -l agents.x-k8s.io/sandbox-name-hash -o name | head -1)
kubectl exec $SANDBOX_POD -n claude-demo -- curl -s http://localhost:8888/
```

Expected: `{"status":"ok"}`

### 7. Watch the agent work

```bash
kubectl logs -f $JOB_POD -c claude-code -n claude-demo
```

You should see:
1. "Waiting for sandbox..." then "Sandbox ready."
2. Claude Code starting with `mcp_servers: [{"name":"sandbox","status":"connected"}]`
3. `sandbox_execute` being called — git/gh commands run locally, npm/node in sandbox
4. No `Bash` tool in the tools list

### 8. (Optional) Deploy the reviewer agent

```bash
envsubst '$TESTING_REPO' < 07-sandbox/agent-sandbox/manifests/reviewer-instance.yaml | kubectl apply -f -
```

### 9. (Optional) Customize the whitelist

To allow additional commands to run locally (e.g., `curl`):

```yaml
spec:
  allowedLocalCommands: "git,gh,curl"
```

## How to Verify

The key indicators that sandbox isolation is working:

1. **Init event** in stream-json output shows:
   - `"mcp_servers":[{"name":"sandbox","status":"connected"}]`
   - `Bash` is NOT in the `"tools"` array
   - `mcp__sandbox__sandbox_execute` IS in the `"tools"` array

2. **Tool calls** show `"name":"mcp__sandbox__sandbox_execute"`

3. **Sandbox pod logs** show HTTP requests hitting the SDK-compatible endpoints:
   ```bash
   kubectl logs $SANDBOX_POD -n claude-demo
   ```

## Cleanup

```bash
# Delete agent instances
kubectl delete claudecodeagentsandbox claude-developer claude-reviewer -n claude-demo --ignore-not-found

# Delete the RGD
kubectl delete -f 07-sandbox/agent-sandbox/manifests/rgd.yaml

# Uninstall agent-sandbox controller
kubectl delete -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.4.3/manifest.yaml
```

## What Changed from Concept 06

| Aspect | Concept 06 | Concept 07 |
|---|---|---|
| Bash execution | Direct in Job pod | Smart routing via MCP: git/gh local, rest → sandbox |
| Isolation | None | Code runs in separate Sandbox pod |
| File sync | N/A | Automatic tar-based sync via SDK filesystem API |
| New dependency | None | `kubernetes-sigs/agent-sandbox` controller |
| Claude Code flags | Standard | `--disallowedTools Bash --mcp-config` |
| Sandbox runtime | N/A | SDK-compatible FastAPI (execute, upload, download, list, exists) |
| Credential model | Proxy for API + git | Proxy for API; git/gh local via proxy; GH_TOKEN to sandbox |
| Configurable | Model, schedule | Model + `allowedLocalCommands` whitelist |
