# GitN Engineering Guidelines

## Purpose

This repository prefers lightweight governance over heavyweight process. The goal is not to document every change. The goal is to keep architecture decisions explicit, stop `RepoViewModel` and `GitService` from absorbing more unrelated work, and bias new behavior toward code that can be covered by unit tests.

Use this document with:

- [AGENTS.md](/Users/user/GitN/AGENTS.md) for active coding rules
- [GitN/DEVELOPMENT.md](/Users/user/GitN/GitN/DEVELOPMENT.md) for codebase structure
- [docs/adr/README.md](/Users/user/GitN/docs/adr/README.md) for long-lived architecture decisions
- [docs/rfcs/README.md](/Users/user/GitN/docs/rfcs/README.md) for change-level design notes

## Default Architecture Rules

- Keep SwiftUI views thin. Views should render state and route actions, not own business rules, parsing, policy, or multi-step workflows.
- Treat view models and services as testable code. New non-trivial logic should be structured so it can run without SwiftUI.
- Do not add new provider-specific hosting, auth, remote parsing, or network request logic to `RepoViewModel`.
- Do not keep expanding `GitService` with unrelated workflow or hosting concerns. Prefer focused helpers and coordinators.
- Prefer extracting behavior into small helpers when the code has stable inputs and outputs, branching rules, or error mapping.
- Prefer shared abstractions over duplicated GitHub/GitLab branches when touching remote parsing, git CLI execution, or HTTP plumbing.

## Testability Standard

New code should maximize unit-testable surface area, not raw coverage numbers.

Required by default:

- Add or update automated tests for any non-UI logic change unless there is a concrete blocker.
- Put transformation, validation, mapping, state transition, action routing, and orchestration logic in types that can be instantiated directly in tests.
- Cover failure paths and edge cases, not only happy paths.
- If UI behavior is hard to test directly, move the underlying logic behind a helper, coordinator, formatter, parser, or view-model method and test that layer.

Avoid:

- Embedding non-trivial branching logic directly in SwiftUI view bodies.
- Hiding important behavior behind `private` view-local closures if the behavior can be extracted and tested.
- Adding new stateful feature logic to large files when it can live in a smaller dedicated type.

## When To Write An RFC

Create an RFC in [docs/rfcs](/Users/user/GitN/docs/rfcs/README.md) before implementation when a change:

- crosses module or screen boundaries
- adds a new service, coordinator, or workflow layer
- changes data flow between View, ViewModel, and Service
- adds a new feature to `RepoViewModel`, `GitService`, or another large hotspot
- introduces non-obvious testing strategy, fake dependencies, or migration behavior

Small bug fixes and local UI-only changes usually do not need an RFC.

## When To Write An ADR

Create or update an ADR in [docs/adr](/Users/user/GitN/docs/adr/README.md) when a change:

- introduces a new architectural pattern or base abstraction
- defines a new long-lived boundary between layers
- changes how hosted review, git execution, networking, persistence, or theming is organized
- standardizes a repository-wide policy that future work should follow

An ADR records a durable decision. An RFC explains a specific change.

## Change Design Checklist

Before implementation, make these decisions explicit:

- Where does the logic live, and why is that layer the right owner?
- What existing hotspot is intentionally not taking more responsibility?
- What code is directly unit-testable after the change?
- What dependencies need fake or test-double seams?
- What failure modes or edge cases must be covered?

## Acceptance Standard For New Logic

A change is aligned with this repo's direction when:

- the main behavior can be exercised without rendering SwiftUI
- new branching logic is concentrated in a small number of focused types
- feature work does not widen `RepoViewModel` or `GitService` without a documented reason
- tests cover the important state transitions, parsing, or orchestration behavior

If a change cannot meet that bar, document the reason in the RFC or PR.
