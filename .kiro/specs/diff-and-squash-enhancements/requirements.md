# Requirements Document

## Introduction

本特性针对 GitN 当前在 “右侧 diff 预览面板” 与 “中间 commit 历史的多选 squash” 两条主流程上的若干体验缺陷做出增强。共有五项变更：

- 预览面板：支持 mp4 等视频文件直接播放（当前仅支持图片）；
- 预览面板：超大 Markdown 文件不再仅以源码（plain text）形式展示，需要在受控阈值内提供 Markdown 渲染；
- 预览面板：在 “File Inspector” 已经停留在 “file too large” 占位状态时，点击列表中其他文件应当正确切换中部内容（当前存在 “选择条变了但中间内容未跟着切” 的回归）；
- Commit Squash：对非连续选中的多个 commit 做 squash 时，能够正确地通过 interactive rebase 先将被选中的 commit 重新排列到 anchor commit 紧邻位置，再标记为 squash；
- Commit Squash：执行 squash 前后包裹一层 `git stash` / `git stash pop`，避免未提交更改干扰交互式 rebase。

非目标（Non-goals）：
- 不引入新的视频转码 / 缩略图生成能力，仅使用 macOS 原生可解码的容器（mp4/mov 等）。
- 不重写 `RepoViewModel` 与 `GitService`；新增逻辑应放在可单元测试的辅助类型 / Service 中（参见 AGENTS.md “Protected Hotspots”）。
- 不改变 commit 历史分页加载与图层布局（`LazyGraphProcessor`、`CommitWalker`）的既有约定。

## Glossary

- **GitN**：本仓库构建的 SwiftUI macOS Git 客户端。
- **File_Inspector**：右侧 diff/preview 面板，由 `RepoViewModel` 中以 `fileInspector*` 为前缀的状态驱动，由 `SourcePreviewView`、`DetailPanelView`、`MarkdownPreviewView`、`CachedDataImageView` 等视图组合呈现。
- **Diff_File_List**：右侧用于罗列变更文件的列表（位于 `DetailPanelView` 中已提交 / 暂存 / 未暂存三个区段）。
- **Preview_Mode**：`File_Inspector` 的 `.preview` 模式，用于以 “可视化” 方式查看单个文件（区别于 diff/history 模式）。
- **Visual_Preview**：在 `Preview_Mode` 下根据文件类型选择的可视化呈现方式（图片、视频、富文本 Markdown 等）；当前仅由 `VisualFileContent` 表达图片与二进制占位。
- **Video_File**：扩展名属于 `Video_Extension_Set` 且能被 macOS `AVFoundation` 解码的文件（初始集合：`mp4`、`m4v`、`mov`、`m4a`）。
- **Video_Extension_Set**：受支持视频扩展名的小写、无前导点的集合，匹配时大小写不敏感。
- **Markdown_File**：扩展名属于 `.md`、`.markdown`、`.mdown`、`.mkd` 之一的文本文件。
- **Markdown_Rich_Preview**：通过 `MarkdownPreviewView` 中 `MarkdownDocumentView` 完成的渲染形式（区别于 plain text 源码视图）。
- **Markdown_Plain_Fallback**：`MarkdownPreviewView` 当前在文件超过 `richPreviewCharacterLimit` / `richPreviewLineLimit` 时回退使用的纯文本视图，工具栏会出现 “Large Markdown shown as plain text”。
- **Markdown_Render_Cap**：可渲染 Markdown 的硬上限字节数，固定为 262 144 字节（256 KB），与 `richPreviewCharacterLimit` 在同一配置源中相邻定义。
- **File_Too_Large_State**：`RepoViewModel.isFileTooLarge == true` 时呈现的占位（“Diff is too large to render”）；该状态为单文件状态，需要随选中文件切换而正确更新。
- **Anchor_Commit**：在 squash 多选场景下，作为合并目标位置的最老 commit，定义为：在所选 commit 中，从 HEAD 沿 first-parent 走链时距离 HEAD 最远的那一个（与现有 `normalizeSquashCommitOrder` 语义一致）。
- **Squash_Set**：除 `Anchor_Commit` 外的其他被选中的 commit 集合；它们将被合并进 `Anchor_Commit`。
- **Squash_Plan**：纯内存数据结构，包含按顺序排列的 todo 行（`pick`/`squash` + 完整 hash）、reorder 决策与 reachable 校验结果；构造过程不得 spawn 子进程、读写磁盘或设置 `GIT_SEQUENCE_EDITOR`。
- **Auto_Stash_Wrapper**：在 squash 操作前后自动执行 `git stash push` / `git stash pop` 的执行包装器；包含失败时的恢复策略与可识别的 stash message。
- **Dirty_Working_Tree**：`git status --porcelain` 输出非空，包含以下任一情形：暂存区或工作区中有 tracked 文件改动、或存在未被 `.gitignore` 忽略的 untracked 文件。补集为 **Clean_Working_Tree**。

## Requirements

### Requirement 1: 视频文件预览

**User Story:** 作为 GitN 用户，当我在右侧 diff 列表中点击一个 mp4 等视频文件时，我希望能直接在预览面板里播放它，而不是看到 “Binary file” 占位，从而完成对资源文件的回归确认。

#### Acceptance Criteria

1. THE GitN SHALL expose a `Video_Extension_Set` on the same path-helper type that also vends `isImageFile`, where the set contains at least the lowercase extensions `mp4`, `m4v`, `mov`, `m4a`, where extensions are stored without a leading dot, and where membership checks are case-insensitive.
2. WHEN a `Diff_File_List` row whose path extension (lowercased, with any leading dot stripped) is a member of `Video_Extension_Set` is opened in `Preview_Mode`, THE File_Inspector SHALL render a `Visual_Preview` that embeds an `AVPlayer`-backed video view bound to the post-image bytes of that diff entry, falling back to the pre-image bytes only when no post-image exists (for example, deletion entries).
3. IF a `Video_File` is opened in `Preview_Mode` and the underlying `AVPlayer` asset surfaces a non-nil load error or resolves its playability status to not-playable, THEN THE File_Inspector SHALL replace the `Visual_Preview` with the same placeholder used for unreadable binary content and SHALL include a message that identifies the file as an unsupported video, without exposing internal error codes or stack details.
4. WHILE a `Video_File` is rendered in `Preview_Mode`, THE File_Inspector SHALL provide a play/pause toggle, a scrub bar that spans the asset's full duration, and a label showing current time and total duration.
5. WHEN a `Video_File` first appears in `Preview_Mode`, THE File_Inspector SHALL leave the asset paused at time zero until the user activates the play control.
6. WHEN the user leaves a `Video_File` in `Preview_Mode` by selecting a different `Diff_File_List` row, dismissing the inspector, or switching the active commit, THE File_Inspector SHALL pause the `AVPlayer`, detach it from the view hierarchy, and release the `AVPlayer` instance before binding any subsequent `Visual_Preview`.
7. IF a `Video_File`'s byte size on disk is greater than the configured `maxDiffFileSize` value, THEN THE File_Inspector SHALL present the existing `File_Too_Large_State` placeholder and SHALL NOT instantiate an `AVPlayer` or load the file's bytes into memory for that selection.
8. THE GitN SHALL cover `Video_Extension_Set` membership (including case-insensitive matches, all four required extensions, and at least one non-video extension that must be rejected) and the size-guarded selection path with unit tests at the helper and view-model layer that execute without instantiating SwiftUI view bodies.

### Requirement 2: 大 Markdown 文件渲染

**User Story:** 作为 GitN 用户，当我预览仓库里的 Markdown 文档时，即便文件较大我也希望看到富文本渲染（标题、列表、代码块），而不是被一刀切到源码模式，以便在 review 阶段更快读懂内容。

#### Acceptance Criteria

1. THE GitN SHALL define `Markdown_Render_Cap` as a single source of truth with the exact value 262 144 bytes (256 KB) and SHALL declare it adjacent to `richPreviewCharacterLimit` in the same configuration source so both constants are visible side by side.
2. WHEN a `Markdown_File` is opened in `Preview_Mode` and its UTF-8 byte length is less than or equal to `Markdown_Render_Cap`, THE File_Inspector SHALL render it via `Markdown_Rich_Preview`, even if the existing line/char heuristics would otherwise trigger `Markdown_Plain_Fallback`.
3. WHEN a `Markdown_File` is opened in `Preview_Mode` and its UTF-8 byte length is greater than `Markdown_Render_Cap`, THE File_Inspector SHALL keep using `Markdown_Plain_Fallback`, SHALL display the persistent indicator "Large Markdown shown as plain text" while the fallback is active, and SHALL attach to that indicator a labeled toolbar button that lets the user opt in to rich rendering for the current file.
4. WHEN the user activates the opt-in control on an over-cap `Markdown_File`, THE File_Inspector SHALL switch only that file's preview to `Markdown_Rich_Preview` for the current preview session, SHALL revert to `Markdown_Plain_Fallback` if the same file is reopened in a later preview session, and SHALL NOT alter the rendering decision for any other file opened before or after.
5. WHILE `Markdown_Rich_Preview` is active for a file, THE File_Inspector SHALL preserve three observable behaviors: zoom controls produce the same scaling factor as before this feature, intra-document anchors scroll to the matching heading, and external links are dispatched through the existing link handler.
6. IF rendering a `Markdown_File` via `Markdown_Rich_Preview` throws an error or fails to produce a first frame within 5 seconds of the render starting, THEN THE File_Inspector SHALL revert to `Markdown_Plain_Fallback` showing the file's complete contents without truncation, AND SHALL surface a non-blocking message describing the fallback.
7. IF a `Markdown_File`'s contents cannot be decoded as UTF-8 or cannot be read from disk, THEN THE File_Inspector SHALL present the existing unreadable-file placeholder and SHALL NOT attempt either `Markdown_Rich_Preview` or `Markdown_Plain_Fallback`.
8. THE GitN SHALL cover the rendering decision with unit tests at the preview-decision helper layer for the following cases: a file equal to `Markdown_Render_Cap` renders rich, a file at `Markdown_Render_Cap` + 1 byte falls back to plain, and the opt-in toggle on a single over-cap file flips only that file's decision while a second over-cap file in the same session continues to fall back to plain.

### Requirement 3: 大文件 / 超限文件之间的切换正确性

**User Story:** 作为 GitN 用户，当我已经在预览一个被判定为 “file too large” 的文件并点击列表中另一个文件时，我希望中间预览区域立刻切换到新选中的文件，而不是保留上一个 “file too large” 占位、让我误以为新文件没有变化。

#### Acceptance Criteria

1. WHEN the user selects a different row in `Diff_File_List`, THE File_Inspector SHALL synchronously, within the same selection handler invocation and before issuing any new content load, reset `isFileTooLarge` to `false`, `fileTooLargeSizeMB` to `nil`, and clear all cached preview state for the previous selection (cached diff text, cached image data, any active `AVPlayer`, any per-file `Markdown_Rich_Preview` opt-in flag).
2. WHEN the user selects a different row, THE File_Inspector SHALL increment `diffLoadGeneration` (or an equivalent monotonic token) at selection time and SHALL discard any payload returned by a load whose token does not match the current value, so that no field tied to the previous selection can be written after the new selection has begun.
3. WHEN selection moves between two files that both exceed `maxDiffFileSize`, THE File_Inspector SHALL update `fileTooLargeSizeMB`, the displayed file name, the displayed repo-relative path, and the change-status indicator to reflect the newly selected file, and SHALL NOT continue to display any of those fields from the previous file.
4. WHEN selection moves from a `File_Too_Large_State` row to a renderable file (text, image, video, or markdown), THE File_Inspector SHALL render the renderable preview as the result of that single selection event, without requiring a second click, keystroke, scroll, or manual refresh, and SHALL NOT render an intermediate stale `File_Too_Large_State` frame.
5. WHEN selection moves from a renderable file back to a `File_Too_Large_State` row, THE File_Inspector SHALL display the size-limit placeholder bound to the new selection's path and size, and SHALL NOT leak the previous file's text, image data, video frames, rendered markdown, path, or size into the placeholder.
6. WHEN the user changes selection again before the load for the previous selection has completed, THE File_Inspector SHALL ensure that the late-arriving load is discarded by the token check from criterion 2, that no preview state is partially populated from the cancelled load, and that the final visible state matches the most recent selection.
7. THE GitN SHALL cover the file-switch correctness paths with view-model-level tests that drive `selectDiffFile` (or its replacement) across all four transition types — TooLarge → TooLarge, TooLarge → renderable, renderable → TooLarge, renderable → renderable — plus a rapid re-selection case where a second selection occurs before the first load completes; each test SHALL assert the post-switch values of `isFileTooLarge`, `fileTooLargeSizeMB`, the active preview kind, and the displayed path.

### Requirement 4: 非连续多选 commit 的 squash 正确性

**User Story:** 作为 GitN 用户，当我从历史中按住 Cmd 选了不连续的几个 commit（例如在 1 2 3 4 5 6（HEAD）中选 5 和 2）并触发 “Squash N Commits” 时，我希望工具自动把 5 移到 2 之后并标记为 squash，得到一个等价于 “手工 `git rebase -i` 重新排序 + s” 的结果，而不是含糊地报错或让顺序错位。

#### Acceptance Criteria

1. THE GitN SHALL extract a dedicated `Squash_Plan` builder from `GitService.squashCommits` that is a pure in-memory function: its construction SHALL NOT spawn a subprocess, read or write the filesystem, or set `GIT_SEQUENCE_EDITOR`, so that the planning step is unit-testable without invoking git.
2. WHEN `squashCommits` is invoked with two or more distinct commit hashes that are all reachable from HEAD on the current branch, THE `Squash_Plan` builder SHALL designate `Anchor_Commit` as the selected commit with the greatest first-parent distance from HEAD (oldest in topo order along the first-parent chain), matching the existing `normalizeSquashCommitOrder` semantics.
3. WHEN the rebase range is defined as the inclusive sequence of commits from `Anchor_Commit` up to and including HEAD, listed oldest-to-newest along the first-parent chain, THE `Squash_Plan` builder SHALL produce a todo list satisfying all of the following: (a) the line for `Anchor_Commit` is `pick <full-hash>` and is the first todo line; (b) every commit in `Squash_Set` appears as `squash <full-hash>` immediately after `Anchor_Commit`'s line, in the same relative order they had in the rebase range; (c) every non-selected commit in the rebase range appears as `pick <full-hash>` after the squash block, preserving their original relative order along the first-parent chain.
4. WHEN GitN executes the resulting `Squash_Plan`, THE `GitService` SHALL run `git rebase -i <Anchor_Commit>^` with `GIT_SEQUENCE_EDITOR` set so that the editor writes the plan's todo lines byte-for-byte (same keywords, full hashes, same order, no extra blank lines, no comment lines beyond what the plan contains), and SHALL NOT prompt the user interactively.
5. IF `squashCommits` is invoked with fewer than two distinct hashes, OR any selected hash is not reachable from HEAD on the current branch, THEN THE `GitService` SHALL fail fast by throwing `GitError.operationFailed` whose message identifies the offending hashes, and SHALL NOT spawn `git rebase`, mutate the working tree, mutate the index, or move any ref.
6. IF `git rebase` exits non-zero (rebase aborted, conflicts, or unexpected error), THEN THE `GitService` SHALL surface a `GitError.operationFailed` carrying the rebase stderr, AND THE `RepoViewModel` SHALL refresh history via `loadAll()` and route any conflict state into the existing conflict toast / banner channel.
7. IF the `Squash_Plan` builder produces a todo list that changes the relative order of any non-selected commit in the rebase range, THEN THE builder SHALL trigger an internal precondition failure that is observable to unit tests (the planner must only move commits in `Squash_Set`).
8. WHEN `git rebase` exits with status zero, THE `RepoViewModel` SHALL refresh history via `loadAll()` and SHALL surface a success toast through the same toast component and presentation as the existing single-commit squash success path, naming the resulting count as |`Squash_Set`| commits squashed into `Anchor_Commit`.
9. THE GitN SHALL ship unit tests for `Squash_Plan` covering: contiguous selection, non-contiguous selection (e.g., {2, 5} out of 1..6 with HEAD at 6), full-range selection, unreachable-hash rejection, and selection cardinality below 2.

### Requirement 5: Squash 操作的 stash 安全包装

**User Story:** 作为 GitN 用户，当我对多个 commit 触发 squash 时，我希望工具自动帮我把工作区里未提交的改动暂存起来，rebase 完成后再恢复，避免 rebase 因为脏工作区中断或丢失我的本地修改。

#### Acceptance Criteria

1. THE GitN SHALL implement an `Auto_Stash_Wrapper` that, given an async git operation, gates its behavior on the result of `git status --porcelain`: when that output indicates a `Dirty_Working_Tree`, the wrapper runs `git stash push --include-untracked --message "GitN: auto-stash before squash"` before the operation and `git stash pop` after the operation; when that output indicates a `Clean_Working_Tree`, the wrapper invokes the operation directly and skips both stash steps to avoid creating an empty stash entry.
2. WHEN `performSquashCommits` is invoked, THE `RepoViewModel` SHALL execute the squash inside `Auto_Stash_Wrapper` regardless of working-tree state, deferring the dirty-vs-clean decision to the wrapper itself.
3. IF `git stash push` exits non-zero before the squash starts, THEN THE `Auto_Stash_Wrapper` SHALL abort the squash, SHALL NOT spawn `git rebase`, AND SHALL surface a `GitError.operationFailed` whose message identifies the stash-push failure with its stderr.
4. WHEN the wrapped squash operation completes successfully AND the wrapper created a stash entry for this invocation, THE `Auto_Stash_Wrapper` SHALL run `git stash pop`; IF that pop exits non-zero or leaves any unmerged paths in `git status --porcelain`, THEN the wrapper SHALL surface the pop-conflict via the existing conflict toast / banner channel without silently swallowing it.
5. IF the wrapped squash operation fails AND the `Auto_Stash_Wrapper` created a stash entry for this invocation, THEN the wrapper SHALL attempt `git stash pop` and SHALL surface a single error containing both the original squash failure description and any pop failure description; otherwise (no stash was created) the wrapper SHALL surface only the original squash failure without invoking `git stash pop`.
6. WHEN `git stash pop` re-introduces merge conflicts (observed as unmerged paths in `git status --porcelain` after the pop), THE `RepoViewModel` SHALL route the user into the existing `ConflictType.stashApply` flow rather than leaving the repo in an unhandled half-state.
7. THE `Auto_Stash_Wrapper` SHALL tag every stash entry it creates with the exact message `"GitN: auto-stash before squash"`, so users can identify and recover the entry manually via `git stash list` if anything goes wrong.
8. THE GitN SHALL cover `Auto_Stash_Wrapper` with service-layer tests for the following cases: clean tree (no stash created, no pop attempted), dirty tree with successful squash and successful pop, dirty tree with successful squash and pop conflict (assert routing into `ConflictType.stashApply`), dirty tree with squash failure where a stash was created (assert combined error + pop attempted), dirty tree with squash failure where stash creation itself failed (assert no rebase spawned), and selection cardinality / preconditions inherited from Requirement 4 are validated before the wrapper engages.
