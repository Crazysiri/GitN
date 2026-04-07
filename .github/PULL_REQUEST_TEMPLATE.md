## Summary

- What changed?
- Why was it needed?
- Link the feature intake in `docs/intake/`.

## Architecture

- Does this change add responsibilities to `RepoViewModel`, `GitService`, or another hotspot?
- If yes, why is that acceptable instead of extracting a dedicated helper/service/coordinator?
- If this is a cross-cutting or non-trivial change, link the RFC or ADR.

## Testing

- What automated tests were added or updated?
- If non-UI logic changed without tests, explain the blocker.
- What manual verification was performed?

## Harness Checklist

- [ ] I added or updated a filled feature intake record in `docs/intake/` for code changes.
- [ ] I updated tests or documented the blocker in the feature intake.
- [ ] If this change needs an RFC or ADR, it is linked above.
