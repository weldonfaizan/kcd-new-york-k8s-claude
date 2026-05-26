#!/usr/bin/env python3
"""
Task dispatcher using the k8s-agent-sandbox Python SDK.

Uses the SDK to claim a warm pool sandbox and execute Claude Code via
sandbox.commands.run(). SDK features leveraged:
- SandboxClaim creation with warm pool adoption
- Direct Pod IP routing (bypasses DNS overhead)
- Automatic retry with exponential backoff on transient failures
- Graceful fallback if RBAC lacks pod IP permissions
- Connection health verification
"""

import json
import os
import sys
import time

from kubernetes import config as k8s_config
k8s_config.load_incluster_config()

from k8s_agent_sandbox import SandboxClient
from k8s_agent_sandbox.models import SandboxInClusterConnectionConfig


def main():
    template_name = os.environ.get("TEMPLATE_NAME", "")
    namespace = os.environ.get("NAMESPACE", "default")
    prompt = os.environ.get("PROMPT", "")
    target_repo = os.environ.get("TARGET_REPO", "")
    agent_task = os.environ.get("AGENT_TASK", "")
    agent_git_name = os.environ.get("AGENT_GIT_NAME", "Claude Agent")
    agent_git_email = os.environ.get("AGENT_GIT_EMAIL", "claude-agent@bot.local")
    anthropic_model = os.environ.get("ANTHROPIC_MODEL", "")
    shutdown_after = int(os.environ.get("SHUTDOWN_AFTER_SECONDS", "0")) or None

    if not template_name:
        print("ERROR: TEMPLATE_NAME is required", file=sys.stderr)
        sys.exit(1)
    if not prompt:
        print("ERROR: PROMPT is required", file=sys.stderr)
        sys.exit(1)

    connection_config = SandboxInClusterConnectionConfig(
        server_port=8888,
        use_pod_ip=True,
    )

    print(f"Claiming sandbox from template '{template_name}'...")
    client = SandboxClient(connection_config=connection_config)

    sandbox = client.create_sandbox(
        template=template_name,
        namespace=namespace,
        warmpool="default",
        shutdown_after_seconds=shutdown_after,
    )

    print(f"Sandbox claimed: {sandbox.sandbox_id}")

    # Configure git in the sandbox
    sandbox.commands.run(f'git config --global user.name "{agent_git_name}"')
    sandbox.commands.run(f'git config --global user.email "{agent_git_email}"')

    # Build the prompt with context
    prompt_parts = []
    if target_repo:
        prompt_parts.append(f"TARGET_REPO={target_repo}")
    if agent_task:
        prompt_parts.append(f"AGENT_TASK={agent_task}")
    prompt_parts.append("")
    prompt_parts.append(prompt)
    full_prompt = json.dumps("\n".join(prompt_parts))

    # Build claude command (model must be provided via env or pool config)
    model = anthropic_model
    if not model:
        print("ERROR: ANTHROPIC_MODEL is required", file=sys.stderr)
        sys.exit(1)
    claude_cmd = (
        f'claude -p --dangerously-skip-permissions --verbose '
        f'--output-format stream-json --model {model} '
        f'-- {full_prompt}'
    )

    print(f"Executing claude (model: {model})...")
    result = sandbox.commands.run(claude_cmd, timeout=3600)

    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

    print(f"=== Dispatch complete (exit: {result.exit_code}) ===")

    sandbox.terminate()
    sys.exit(0 if result.exit_code == 0 else 1)


if __name__ == "__main__":
    main()
