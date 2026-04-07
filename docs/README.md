# GitN Documentation

This directory is the entrypoint for repository-level engineering docs.

Use these docs in this order:

1. Start here to decide which document you need.
2. Read [ENGINEERING_WORKFLOW.md](/Users/user/GitN/docs/ENGINEERING_WORKFLOW.md) before implementing a feature or non-trivial refactor.
3. Read [ENGINEERING_GUIDELINES.md](/Users/user/GitN/docs/ENGINEERING_GUIDELINES.md) when you need the policy behind layer ownership, testability, or design-record requirements.
4. Use [rfcs/README.md](/Users/user/GitN/docs/rfcs/README.md) and [adr/README.md](/Users/user/GitN/docs/adr/README.md) when the workflow says a design record is required.

## Document Map

| Document | Purpose | Read It When |
| --- | --- | --- |
| [AGENTS.md](/Users/user/GitN/AGENTS.md) | Active coding rules and execution-time guardrails | You are about to make changes in this repo |
| [GitN/DEVELOPMENT.md](/Users/user/GitN/GitN/DEVELOPMENT.md) | Codebase map, data flow, and hotspot orientation | You need to understand where code lives |
| [ENGINEERING_WORKFLOW.md](/Users/user/GitN/docs/ENGINEERING_WORKFLOW.md) | Mandatory pre-implementation harness | You are defining feature scope, ownership, and test plan |
| [ENGINEERING_GUIDELINES.md](/Users/user/GitN/docs/ENGINEERING_GUIDELINES.md) | Durable engineering policy and testability standard | You need a policy decision, not just a checklist |
| [docs/templates/feature-intake-template.md](/Users/user/GitN/docs/templates/feature-intake-template.md) | Lightweight planning artifact for feature work | The change needs structure but not a full RFC |
| [docs/intake/README.md](/Users/user/GitN/docs/intake/README.md) | Filled feature intake records | You need to create or review the actual intake artifact for a change |
| [rfcs/README.md](/Users/user/GitN/docs/rfcs/README.md) | Change-level design records | The workflow says the change needs an RFC |
| [adr/README.md](/Users/user/GitN/docs/adr/README.md) | Long-lived architecture decisions | The workflow says the change needs an ADR |

## Source Of Truth

- `AGENTS.md` is the operational rulebook for work in progress.
- `GitN/DEVELOPMENT.md` is the source of truth for codebase orientation and current hotspots.
- `ENGINEERING_WORKFLOW.md` is the source of truth for pre-implementation intake.
- `docs/intake/` is the source of truth for completed feature intake records in active changes.
- `ENGINEERING_GUIDELINES.md` is the source of truth for layer ownership and testability policy.
- `docs/rfcs/` and `docs/adr/` are the source of truth for design-record formats and expectations.

If two docs overlap, follow the more specific source-of-truth owner above and update the summary copy to point back to it.
