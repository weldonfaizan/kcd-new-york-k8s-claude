# CLAUDE.md

## Project

Reference implementation for KCD New York 2026 talk: "Platform Engineering for AI Agents: Secure Claude Code on Kubernetes with KRO"

## Structure

- Each concept is a numbered directory (`01-kind-cluster/`, `02-claude-k8s-job/`, etc.)
- Concepts are progressive — each builds on the previous
- Each concept is self-contained with its own README and manifests
- The numbered prefix is load-bearing — do not reorder

## Conventions

- Kubernetes manifests: lowercase-hyphenated filenames (e.g., `cronjob.yaml`)
- Shell scripts: `*.sh` with shebang `#!/bin/bash` and `set -euo pipefail`
- All manifests use namespace `claude-demo`
- Claude Code model: always use `--model` flag explicitly with `claude-haiku-4-5-20251001`
- Claude Code mode: always use `--bare --dangerously-skip-permissions --print` flags (API key auth, no OAuth, non-interactive)
- Never commit real credentials — use `REPLACE_ME` placeholders in manifests
- Real credentials go in `.env` (gitignored), loaded via `source .env`

## README Template (per concept)

Each concept README follows: Concept Summary, Prerequisites, Step-by-Step, How to Verify, Expected Output, Cleanup

## Prompts

- Concepts 02-03: prompt delivered via inline env var (`CLAUDE_PROMPT`)
- Concepts 04-05: prompt stored in `prompts/*.md`, delivered via ConfigMap volume mount

## Testing

- Default test repo: `csantanapr/kcd-nyc-hello` (private, accessible via GH_TOKEN)
- Kind cluster name: `claude-demo`
- Always test with haiku model for cost efficiency
