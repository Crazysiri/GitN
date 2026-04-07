# Feature Intake Records

Store lightweight pre-implementation planning records here.

Use this directory when a change needs a written feature intake but does not need a full RFC on its own.

## Naming

Use this filename format:

- `YYYY-MM-DD-short-slug.md`

Examples:

- `2026-04-07-remote-branch-delete-feedback.md`
- `2026-04-08-hosted-review-toolbar-state.md`

## Workflow

1. Start from [docs/templates/feature-intake-template.md](/Users/user/GitN/docs/templates/feature-intake-template.md).
2. Save the filled document in this directory before implementation.
3. If the intake concludes that the change also needs an RFC or ADR, add those records in `docs/rfcs/` or `docs/adr/` and link them from the PR.

## CI Enforcement

The repository harness check expects a filled intake record in this directory for code changes in `GitN/Sources/GitN`, `GitN/Tests/GitNTests`, or `GitN/Package.swift`.

The check is intentionally lightweight:

- it verifies that an intake record exists in the diff
- it rejects obvious template placeholders
- it does not try to replace engineering judgment about when an RFC or ADR is needed
