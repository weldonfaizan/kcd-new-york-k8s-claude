#!/bin/bash
set -euo pipefail

git config --global user.email "claude-developer@bot.local"
git config --global user.name "Claude Developer"


# Use a sentinel file to track whether a previous session exists
PREV_RUN_FLAG="/home/claude/.claude/.agent-ran"

PROMPT=$(cat /prompts/developer.md)
PROMPT="TARGET_REPO=${TARGET_REPO}
FEATURE_REQUEST=${FEATURE_REQUEST}

${PROMPT}"

echo "Starting Claude Code Developer Agent..."
echo "Target repo: ${TARGET_REPO}"
echo "Feature: ${FEATURE_REQUEST}"
echo "Model: ${ANTHROPIC_MODEL}"
echo "---"

if [ -f "$PREV_RUN_FLAG" ]; then
  echo "Previous session found — resuming with --continue"
  exec claude -p --dangerously-skip-permissions --verbose --output-format stream-json \
    --continue --model "${ANTHROPIC_MODEL}" -- "${PROMPT}"
else
  echo "First run — starting fresh session"
  claude -p --dangerously-skip-permissions --verbose --output-format stream-json \
    --model "${ANTHROPIC_MODEL}" -- "${PROMPT}"
  touch "$PREV_RUN_FLAG"
fi
