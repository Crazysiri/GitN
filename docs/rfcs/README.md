# RFCs

Use this directory for change-level design notes.

Every feature should start with the pre-implementation flow in [docs/ENGINEERING_WORKFLOW.md](/Users/user/GitN/docs/ENGINEERING_WORKFLOW.md). An RFC is the escalation path for changes that need a written design before code is written, but do not necessarily require a permanent architecture record on their own.

RFCs are expected for:

- cross-screen or cross-module changes
- additions to major hotspots such as `RepoViewModel` or `GitService`
- new services, coordinators, workflow layers, or testing seams
- changes that need non-obvious unit-test strategy

An RFC should answer:

- what behavior is changing
- what is in scope and out of scope
- where the logic will live and why
- how data flow or ownership changes
- what alternatives were considered
- what tests will prove the change

Done means another engineer can implement the change without inventing missing ownership, test, or migration policy.

An RFC explains a specific change. If the change also creates a long-lived repository decision, pair it with an ADR.

Start from [docs/rfcs/0000-template.md](/Users/user/GitN/docs/rfcs/0000-template.md).
