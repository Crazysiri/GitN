# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-05-08

## Summary

修复提交 diff 中部分 Markdown 文件进入文件检查器后未展示 patch 的问题。当前从 diff 入口打开 `.md` 文件时，检查器初始模式会被强制改成 preview，导致用户看不到该提交的文本 diff。本次调整只修改文件检查器的初始模式选择，让 diff 入口尊重 `.diff` 请求。

## Behavior Change

- 从 committed/staged/unstaged diff 入口打开 Markdown 文件时，文件检查器默认进入 diff 模式并展示 patch。
- 显式 preview 入口仍然打开 Markdown 预览。
- file history 模式和底层 Git diff 读取逻辑保持不变。

## Non-Goals

- 不修改 GitService 的 commit diff / file history / compare diff 解析逻辑。
- 不改变 Markdown 预览组件或其渲染效果。
- 不调整 history 模式的展示行为。

## Change Boundary

- In scope:
  - 文件检查器初始模式决策。
  - 覆盖 Markdown diff 与 preview 路径的测试。
- Out of scope:
  - Git diff 生成、history diff、compare diff、working tree file preview。
- Protected hotspots reviewed:
  - `RepoViewModel`: 仅修改已有 UI 模式决策，不向其增加新的跨层职责。
  - `GitService`: 不改动。

## Ownership

- Primary owner layer: ViewModel
- Why this layer is the right owner: 问题来自文件检查器入口的模式选择，是界面状态编排，不是 Git 数据获取或解析问题。
- Which larger type is intentionally not taking more responsibility: `GitService` 不承担 Markdown 展示策略。

## Affected Areas

- Screens / flows:
  - 提交 diff 文件列表打开文件检查器
  - staged/unstaged diff 文件列表打开文件检查器
- Services / helpers / view models:
  - `RepoViewModel`
- Files likely to change:
  - `GitN/Sources/GitN/Models/RepoViewModel.swift`
  - `GitN/Tests/GitNTests/DiffContentLogicTests.swift`

## Test Scope

- Unit tests:
  - Markdown 文件从 diff 入口打开时保持 diff 模式。
  - Markdown 文件从 preview 入口打开时仍保持 preview。
- Integration tests:
  - 无。
- Manual verification:
  - 打开目标仓库提交 `0af8d2c84e754b40ec37df5c255f8c89743657da`，确认 `.planning/ROADMAP.md` 能在 inspector 中显示 diff。
- Failure modes / edge cases:
  - 不应让显式 preview 入口退化为 diff。
  - 不应影响 history 模式。
- Known coverage blockers:
  - 无。

## Design Records

- RFC required? Why or why not?
  - No. 这是局部 bug fix，只调整现有 ViewModel 的 UI 模式决策，不引入新边界或跨模块流程。
- ADR required? Why or why not?
  - No. 不涉及长期架构决策或仓库级策略变更。

## Completion Criteria

- Markdown 文件从 diff 入口打开时显示 diff。
- Markdown 文件从 preview 入口打开时仍显示预览。
- 现有非 Markdown / history 相关行为未回归。

## Open Questions

- 无。
