# GitN Engineering Workflow

Use this workflow before implementing any feature, refactor, or non-trivial bug fix.

The goal is to make the change explicit before code is written:

1. define the behavior change
2. define the boundary
3. choose the owner
4. define the test scope
5. decide whether intake only, RFC, ADR, or both are required

## Required Flow

### Step 1: Define The Change

Write down:

- a one-paragraph summary of the change
- the user-visible or developer-visible behavior change
- explicit non-goals
- completion criteria

If you cannot state what is changing and what is not changing, stop here and narrow the work.

### Step 2: Define The Boundary

List the intended scope before editing:

- affected screens, flows, or services
- expected files or subsystems in scope
- major hotspots that should not absorb new responsibility by default
- neighboring areas intentionally out of scope

For GitN, treat these as protected hotspots:

- `RepoViewModel`
- `GitService`
- provider-specific GitHub/GitLab service branches

If the change would add new feature orchestration, network logic, remote parsing, or provider-specific policy to one of those hotspots, document why extraction is not the better default.

### Step 3: Choose The Owner

Decide which layer owns the new behavior:

- View: presentation, layout, rendering-only state, action wiring
- ViewModel: screen state and orchestration when it must coordinate existing services
- Service/helper/coordinator/parser/formatter: non-trivial logic, transformations, request plumbing, state machines, policy, parsing, validation

Record:

- the chosen owner
- why that layer is the right owner
- which larger type is intentionally not taking more responsibility

### Step 4: Define Test Scope

Decide the minimum required coverage before coding:

- unit tests for parsing, mapping, policy, state transitions, orchestration, validation, and failure paths
- integration tests when behavior crosses boundaries and can be exercised without UI rendering
- manual verification for UI rendering and user flows that are hard to automate

Also record:

- failure modes that must be covered
- manual checks that remain necessary
- any concrete blocker preventing automated coverage

### Step 5: Create The Intake Record

Every feature starts with a feature intake. Use [docs/templates/feature-intake-template.md](/Users/user/GitN/docs/templates/feature-intake-template.md) and save the filled record in [docs/intake/](/Users/user/GitN/docs/intake/README.md) unless an equivalent planning artifact already exists in the task and is linked from the PR.

The harness check expects this artifact for code changes.

Escalate from there using this matrix:

| Change shape | Required artifact |
| --- | --- |
| Local UI-only change with clear ownership and no policy impact | Feature intake only |
| Local non-UI behavior change with a clear owner and test plan | Feature intake only |
| Cross-screen or cross-module feature | Feature intake + RFC |
| New service, coordinator, workflow layer, or non-obvious testing seam | Feature intake + RFC |
| Non-trivial addition to `RepoViewModel` or `GitService` | Feature intake + RFC |
| New long-lived architectural boundary or repository-wide policy | Feature intake + ADR |
| Feature that both changes implementation flow and establishes a durable architectural decision | Feature intake + RFC + ADR |

If the safest answer is unclear, default to writing the RFC.

### Step 6: Confirm Implementation Readiness

Do not start coding until the following are written down:

- summary
- behavior change
- non-goals
- intake file path
- boundary
- owner
- test scope
- required design records
- completion criteria

## Completion Gate

Before considering the change ready to merge, verify:

- the implementation still matches the documented boundary
- tests match the documented test scope or the gap is explicitly noted
- any required RFC or ADR was written before or alongside implementation
- any new durable rule is reflected in the right source-of-truth doc
- the PR explains why the logic lives in its chosen layer and what is directly unit-testable

## Expected Outputs By Change Size

| Change size | Minimum written artifact | Typical validation |
| --- | --- | --- |
| Small UI change | Feature intake | Manual verification, plus tests if non-UI logic moved out of the view |
| Focused feature or bug fix with logic changes | Feature intake | Unit tests for extracted logic, targeted manual verification |
| Cross-cutting feature or refactor | Feature intake + RFC | Unit/integration coverage and multi-flow manual verification |
| Durable architecture change | Feature intake + ADR, often RFC too | Tests for new seams plus follow-up documentation updates |
