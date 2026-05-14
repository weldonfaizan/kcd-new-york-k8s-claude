# 08 - Network Policy for Non-HTTP Traffic

For database/SSH access, the `allow-everything` mode + NetworkPolicy is the right pattern — let the proxy handle credential injection for HTTPS domains, and let Kubernetes NetworkPolicy handle the L3/L4 filtering for everything else.

## Goals

- Demonstrate proxy in `allow-everything` mode (only credential-replace for listed domains, pass through everything else)
- Use Kubernetes NetworkPolicy to restrict which IPs/pods the agent can reach over raw TCP
- Example: allow the agent to connect to a PostgreSQL pod in the same namespace, block everything else at the network level

## Key Concepts

- The transparent proxy handles **application-layer** (L7) concerns: hostname allowlisting, credential injection
- NetworkPolicy handles **network-layer** (L3/L4) concerns: which IPs and ports are reachable
- Together they provide defense-in-depth without needing protocol-aware proxying for every protocol
