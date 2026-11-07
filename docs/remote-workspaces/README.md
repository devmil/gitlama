# Remote workspaces over SSH

A remote workspace operates an existing repository on another computer, including that computer's working tree and index. It is different from cloning or fetching a Git remote over SSH. GitLama installs a small helper on the host and talks to it over the user's existing OpenSSH configuration; Git and filesystem work run on the host, GitLama displays the results locally.

Read in this order:

1. [Architecture](ARCHITECTURE.md): ownership, SSH boundary, helper, protocol, identities, persistence and failure semantics.
2. [Protocol](PROTOCOL.md): the wire contract shared by the helper and the client.
3. [Setup](SETUP.md): how a user prepares a host and installs the helper manually.

Remote hosts run Linux (x86_64 and arm64) or macOS (Apple silicon and Intel). Writes are admitted only with durable operation receipts and disconnect reconciliation. The helper's compatibility version is described in [AGENTS.md](../../AGENTS.md#remote-helper-compatibility). Where this folder changes an assumption for remote sessions, it states the exception explicitly; local sessions retain the contract of the [application architecture](../ARCHITECTURE.md).
