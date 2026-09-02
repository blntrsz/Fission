# Fission

Fission organizes work performed by software agents into durable workstreams shared across its applications.

## Language

**Thread**:
A long-lived agent workstream that groups related agent activity across one objective or conversation.
_Avoid_: Agent work, execution, run

**Run**:
One agent execution within a Thread. A Run may succeed or fail without ending its Thread.
_Avoid_: Thread, agent work

**Settled Thread**:
A Thread intentionally closed to further active work. A Run succeeding, failing, or being cancelled does not settle its Thread.
_Avoid_: Completed Thread, archived Thread

**Agent Activity**:
A transient attention state for an agent in a Thread: Idle, Running, Blocked, or Finished. It is distinct from the Thread lifecycle and defaults to Idle when no activity is known.
_Avoid_: Working state, Thread status

**Finished Activity**:
Agent activity that completed and has not yet been acknowledged by selecting its Thread. Acknowledgement returns the activity to Idle.
_Avoid_: Unread agent, completed Thread
