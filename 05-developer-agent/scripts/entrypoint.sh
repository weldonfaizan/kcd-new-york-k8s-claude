#!/bin/bash
set -e

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

CLAUDE_ARGS="-p --dangerously-skip-permissions --verbose --output-format stream-json --model ${ANTHROPIC_MODEL}"

if [ -f "$PREV_RUN_FLAG" ]; then
  echo "Previous session found — resuming with --continue"
  CLAUDE_ARGS="$CLAUDE_ARGS --continue"
else
  echo "First run — starting fresh session"
fi

RAW_LOG="/tmp/claude-raw-$(date +%s).jsonl"
CLAUDE_EXIT=0

timeout 3600 claude $CLAUDE_ARGS -- "$PROMPT" \
  | tee "$RAW_LOG" \
  | jq --unbuffered -r '
if .type == "assistant" then
  .message.content[]? |
  if .type == "text" then ">>> " + .text[0:5000]
  elif .type == "tool_use" then "[" + .name + "] " + ((.input | tostring)[0:3000])
  else empty end
elif .type == "result" then
  "[done] " + (.result // "complete")[0:5000]
else empty end' || CLAUDE_EXIT=$?

# Mark session for resume on next run
if [ "$CLAUDE_EXIT" -eq 0 ]; then
  touch "$PREV_RUN_FLAG"
fi

# If Claude timed out, salvage partial results
if [ "$CLAUDE_EXIT" -eq 124 ]; then
  echo "=== TIMEOUT: Claude exceeded time limit ==="
  timeout 300 claude -p --dangerously-skip-permissions -- \
    "The previous process timed out. Check what partial results exist and write a summary to /tmp/partial-report.md."
fi

echo "=== Complete (exit: $CLAUDE_EXIT) ==="
