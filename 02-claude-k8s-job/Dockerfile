FROM node:22-slim

# Install git, curl, Python, Go, and GitHub CLI
RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    golang-go \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Install Python packages for sandbox integration (concept 07)
# - fastmcp: MCP server framework for Claude Code tool integration
# - fastapi + uvicorn: SDK-compatible sandbox runtime API
# - requests: HTTP client for sandbox communication
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install fastmcp fastapi uvicorn requests
ENV PATH="/opt/venv/bin:$PATH"

# Create non-root user
RUN useradd -m -s /bin/bash claude
USER claude
WORKDIR /home/claude

# Claude Code runs in non-interactive print mode
ENTRYPOINT ["claude"]
