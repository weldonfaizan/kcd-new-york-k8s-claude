# 06 - KRO ClaudeCodeAgent Abstraction

Define a `ClaudeCodeAgent` custom resource using [KRO](https://kro.run/) that encapsulates the entire agent pattern (sidecar proxy, entrypoint, PVCs) behind a simple API. One resource replaces the copy-paste boilerplate from concepts 04 and 05.

## What KRO Generates

From a single `ClaudeCodeAgent` instance, KRO creates 5 resources:

| # | Resource | Condition |
|---|----------|-----------|
| 1 | ConfigMap (entrypoint + prompt + env vars) | Always |
| 2 | PVC (workspace for cloned repos) | Always |
| 3 | PVC (Claude memory for session resume) | Always |
| 4 | Job (one-shot agent) | `schedule == ""` |
| 5 | CronJob (recurring agent) | `schedule != ""` |

## Prerequisites

- Completed concepts 01-05 (Kind cluster running, images built)
- [KRO installed](https://kro.run/docs/getting-started/Installation) in the cluster
- Secret `agent-credentials` exists in `claude-demo` namespace

## Step-by-Step

### 1. Install KRO (if not already installed)

```bash
# Check if kro is running
kubectl get pods -n kro-system

# If not installed:
helm install kro oci://registry.k8s.io/kro/charts/kro \
  --namespace kro-system \
  --create-namespace

# Learn more: https://kro.run/docs/getting-started/Installation
```

### 2. Apply the ResourceGraphDefinition

```bash
kubectl apply -f 06-kro-agent/manifests/rgd.yaml
```

Verify the CRD was generated:

```bash
kubectl get crd claudecodeagents.kro.run
```

### 3. Deploy a Reviewer (CronJob mode)

```bash
set -a && source ../../.env && set +a
envsubst '$TESTING_REPO' < 06-kro-agent/manifests/reviewer-instance.yaml | kubectl apply -f -
```

### 4. Deploy a Developer (Job mode)

```bash
set -a && source ../../.env && set +a
envsubst '$TESTING_REPO' < 06-kro-agent/manifests/developer-instance.yaml | kubectl apply -f -
```

## How to Verify

```bash
# Check the custom resources
kubectl get claudecodeagent -n claude-demo

# See what KRO created for the reviewer (CronJob + ConfigMap + PVCs)
kubectl get configmap,pvc,cronjob -n claude-demo -l app.kubernetes.io/managed-by=kro

# See what KRO created for the developer (Job + ConfigMap + PVCs)
kubectl get configmap,pvc,job -n claude-demo -l app.kubernetes.io/managed-by=kro

# Trigger a manual reviewer run
kubectl create job --from=cronjob/claude-reviewer claude-reviewer-manual -n claude-demo

# Watch logs
kubectl logs job/claude-reviewer-manual -c claude-code -n claude-demo -f
kubectl logs job/claude-developer -c claude-code -n claude-demo -f

# Verify fake credentials in main container (not real secrets)
kubectl exec job/claude-developer -c claude-code -n claude-demo -- env | grep -E 'API_KEY|GH_TOKEN'
```

## Expected Output

```
# kubectl get claudecodeagent -n claude-demo
NAME               AGE
claude-reviewer    10s
claude-developer   5s

# kubectl get configmap,pvc,cronjob,job -n claude-demo
NAME                              DATA   AGE
configmap/claude-reviewer-config  8      10s
configmap/claude-developer-config 8      5s

NAME                                        STATUS   CAPACITY   AGE
persistentvolumeclaim/claude-reviewer-workspace   Bound    5Gi        10s
persistentvolumeclaim/claude-reviewer-memory       Bound    1Gi        10s
persistentvolumeclaim/claude-developer-workspace  Bound    5Gi        5s
persistentvolumeclaim/claude-developer-memory      Bound    1Gi        5s

NAME                           SCHEDULE       SUSPEND   ACTIVE
cronjob.batch/claude-reviewer  0 */4 * * *    False     0

NAME                        COMPLETIONS   DURATION   AGE
job.batch/claude-developer  0/1           5s         5s
```

## Cleanup

```bash
# Delete instances (KRO garbage-collects all child resources)
kubectl delete claudecodeagent claude-reviewer claude-developer -n claude-demo

# Remove the RGD
kubectl delete -f 06-kro-agent/manifests/rgd.yaml
```

## Comparison: Before and After KRO

**Before (concept 04/05):** Each agent requires manually creating a ConfigMap, Job/CronJob, and PVCs with ~100 lines of YAML, duplicating the sidecar proxy pattern.

**After (concept 06):** A single `ClaudeCodeAgent` resource with ~20 lines of user-facing YAML. The platform team maintains the RGD; developers just specify their agent name, repo, and prompt.
