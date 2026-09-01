# Fission

Fission organizes work performed by software agents into durable workstreams shared across its applications.

## Language

**Thread**:
A long-lived agent workstream that groups related agent activity across one objective or conversation.
_Avoid_: Agent work, execution, run

**Run**:
One agent execution within a Thread. A Run may succeed or fail without ending its Thread.
_Avoid_: Thread, agent work
