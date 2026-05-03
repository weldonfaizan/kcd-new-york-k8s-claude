# Future Concepts

Planned extensions to the platform engineering patterns demonstrated in this repo.

---

## E2B Sandbox for Bash Tool Isolation (Coming Soon)

Instead of Claude Code running bash commands directly inside the pod, route all code execution to an [E2B](https://e2b.dev/) remote sandbox.

### Why

Defense in depth — even if the agent is compromised or generates dangerous commands, it cannot affect the host pod's filesystem, network, or other containers. The sandbox is ephemeral and isolated.

### How

Using Claude Code's **PreToolUse hooks**, bash commands are intercepted before execution and forwarded to an E2B sandbox:

```
Claude Code wants to run: npm test
       │
       ▼
PreToolUse Hook fires
       │
       ▼
Hook modifies command: e2b-run "npm test"
       │
       ▼
Local bash runs the wrapper
       │
       ▼
Wrapper creates E2B sandbox, runs command, returns output
       │
       ▼
Claude sees results as if they ran locally
```

File operations (Read/Write/Edit) remain local. Only bash execution is sandboxed.
