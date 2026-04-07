# ADRs

Use this directory for architecture decision records.

Every feature should start with the pre-implementation flow in [docs/ENGINEERING_WORKFLOW.md](/Users/user/GitN/docs/ENGINEERING_WORKFLOW.md). Write an ADR when a decision is expected to survive beyond one feature or PR, especially when it changes layer boundaries, shared abstractions, or repository-wide policy.

Typical ADR topics:

- splitting responsibilities out of `RepoViewModel`
- introducing a shared code-hosting transport or git runner abstraction
- standardizing where state, orchestration, or parsing logic belongs
- setting a durable testing policy for a subsystem

An ADR should answer:

- what durable problem or decision driver exists
- what boundary, policy, or abstraction is being standardized
- what alternatives were rejected
- what future work must now follow from this decision

Done means future changes can use the ADR as the repository-wide rule instead of reopening the same architecture decision in each feature RFC or PR.

An ADR records a durable decision. If a specific feature also needs design detail for implementation, pair the ADR with an RFC.

Start from [docs/adr/0000-template.md](/Users/user/GitN/docs/adr/0000-template.md).
