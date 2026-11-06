# ADR: serialize repository mutations at service entry

- Status: Accepted
- Date: 2026-11-06

All app-owned GitService writes and WorktreeService mutations acquire a shared gate keyed by canonical Git common directory. Actor isolation alone is insufficient across awaits. Keep queue ownership outside the implementation helpers so composite operations retain a single lease. Read-only APIs do not acquire the write gate. This conservatively serializes linked worktrees sharing references as well as duplicate tabs. External Git processes remain governed by Git lockfiles and snapshot validation.

Future mutation APIs must use this boundary and must not call internal unqueued methods from UI code. Cross-service multi-step workflows need an explicit transaction design before adding a nested gate.
