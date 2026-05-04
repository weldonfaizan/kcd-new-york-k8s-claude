#!/bin/bash
set -e

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

# Run Claude Code with stream-json output, filtered through jq for readable logs
claude -p --dangerously-skip-permissions --verbose --output-format stream-json \
  --model "${ANTHROPIC_MODEL}" -- "${PROMPT}" \
  | jq --unbuffered -r '
if .type == "assistant" then
  .message.content[]? |
  if .type == "text" then ">>> " + .text[0:5000]
  elif .type == "tool_use" then "[" + .name + "] " + ((.input | tostring)[0:3000])
  else empty end
elif .type == "result" then
  "[done] " + (.result // "complete")[0:5000]
else empty end'
