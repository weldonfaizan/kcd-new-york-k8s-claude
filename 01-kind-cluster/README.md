# 01 - Kind Cluster

Create a local Kubernetes cluster using [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker) for testing all subsequent concepts.

The setup script is idempotent — it creates the cluster (if not exists), all namespaces for concepts 02-07, and injects credentials from `.env` as Kubernetes Secrets. Re-run it anytime to refresh secrets after editing `.env`.

## Authentication Modes

The script supports two modes for authenticating Claude Code in pods:

| Mode | How pods authenticate | Requirements |
|------|----------------------|--------------|
| `bedrock` (default) | EC2 metadata → IAM role → Amazon Bedrock | `aws-vault`, `socat`, AWS profile with Bedrock permissions |
| `api-key` | `ANTHROPIC_API_KEY` in Secret | Anthropic API key in `.env` |

### Bedrock Mode (default)

Pods get AWS credentials automatically via the EC2 instance metadata endpoint (`169.254.169.254`). The script:

1. Starts an `aws-vault` EC2 metadata server on the host
2. Sets up `socat` bridges so Kind pods can reach it
3. Creates secrets with only `GH_TOKEN` (no API key needed)

Pods must set `CLAUDE_CODE_USE_BEDROCK=1` and `AWS_REGION=us-west-2` to use this mode.

The metadata server runs until the terminal closes. Re-run the script to restart it.

### API Key Mode

Classic mode — the `ANTHROPIC_API_KEY` from `.env` is injected as a Kubernetes Secret.

```bash
AUTH_MODE=api-key bash scripts/create-cluster.sh
```

## Prerequisites

- Docker running
- `kind` CLI installed ([install guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- `kubectl` installed
- For Bedrock mode: `aws-vault`, `socat`, and a configured AWS profile (see below)

### AWS Profile Setup (Bedrock mode)

Create an IAM role with Bedrock invoke permissions and an AWS CLI profile that assumes it:

```bash
# Create role
aws iam create-role --role-name BedrockClaudeInvoke \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::ACCOUNT_ID:root"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach Bedrock invoke policy
aws iam put-role-policy --role-name BedrockClaudeInvoke \
  --policy-name BedrockClaudeAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
      "Resource": [
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:ACCOUNT_ID:inference-profile/*anthropic*"
      ]
    }]
  }'
```

Add the profile to `~/.aws/config`:

```ini
[profile bedrock-claude]
role_arn=arn:aws:iam::ACCOUNT_ID:role/BedrockClaudeInvoke
source_profile=your-admin-profile
region=us-west-2
```

## Step-by-Step

```bash
# Default (Bedrock mode)
bash scripts/create-cluster.sh

# Or with API key
AUTH_MODE=api-key bash scripts/create-cluster.sh

# Custom aws-vault profile
AWS_VAULT_PROFILE=my-profile bash scripts/create-cluster.sh
```

## How to Verify

```bash
kubectl cluster-info --context kind-claude-demo
kubectl get nodes
```

## Expected Output

```
Kubernetes control plane is running at https://127.0.0.1:XXXXX

NAME                        STATUS   ROLES           AGE   VERSION
claude-demo-control-plane   Ready    control-plane   30s   v1.31.0
```

## Cleanup

```bash
kind delete cluster --name claude-demo
```
