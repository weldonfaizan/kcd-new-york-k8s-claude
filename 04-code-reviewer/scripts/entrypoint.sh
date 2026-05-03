#!/bin/bash
set -euo pipefail

# Configure git identity
git config --global user.email "claude-reviewer@bot.local"
git config --global user.name "Claude Reviewer"

# GitHub CLI auth via token

# Read the prompt from the mounted file
PROMPT=$(cat /prompts/reviewer.md)

# Inject TARGET_REPO into the prompt context
PROMPT="TARGET_REPO=${TARGET_REPO}

${PROMPT}"

echo "Starting Claude Code Reviewer..."
echo "Target repo: ${TARGET_REPO}"
echo "Model: ${ANTHROPIC_MODEL}"
echo "---"

# Run Claude Code in non-interactive mode
exec claude -p --dangerously-skip-permissions --verbose --output-format stream-json \
  --model "${ANTHROPIC_MODEL}" -- "${PROMPT}"
