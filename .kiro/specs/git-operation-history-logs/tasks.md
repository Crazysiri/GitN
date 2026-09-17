# 实现计划：Git 操作历史日志（git-operation-history-logs）

## Overview

本计划将设计文档自底向上拆分为可增量交付的编码任务：先建立纯数据模型（`OperationLogEntry` / `OperationOutput` / `GitOperationKind`），再实现持久化层 `OperationHistoryStore`，随后是聚焦服务 `OperationHistoryService` 与 `@Observable` 投影 `OperationHistoryState` + 视图模型，接着新增 `GitCLI` 邻域的 `GitStreamingExecutor` 流式执行路径，然后在 `RepoViewModel` 做 orchestration-only 接线（远程流式操作与本地捕获类变更），最后接入工具栏的 `HistoryView` UI。

每一步都建立在前一步之上，并在末尾把组件接线在一起，避免出现游离、未集成的代码。非 UI 的模型/服务/持久化/执行器层随附单元测试、属性测试（≥100 迭代）以及 EDGE_CASE / INTEGRATION / SMOKE 检查；测试风格对齐既有 `RepoReflogLoaderTests` 与 `TemporaryGitRepository`。属性测试统一打标签 `Feature: git-operation-history-logs, Property {n}`。

## Tasks

- [x] 1. 建立数据模型层（`OperationLogEntry` / `OperationOutput` / `GitOperationKind`）
  - [x] 1.1 定义 `GitOperationKind` 与 `OperationResult` 枚举
    - 在 `GitN/Sources/GitN/Models/` 下新增 `OperationLogEntry.swift`
    - 定义 `GitOperationKind`（streaming：fetch/fetchPrune/pull/pullFF/pullRebase/pullForce/push/pushForce/pushTag；本地变更类：commit/merge/rebase/checkout/reset/stash），实现 `isStreaming` 计算属性
    - 定义 `OperationResult`（running/success/failure/interrupted），均为 `Codable, Sendable`
    - _Requirements: 1.1, 1.3, 3.4_

  - [x] 1.2 实现 `OperationOutput` 字节存储与有损解码视图
    - 以 `Data` 为权威存储 `stdout`/`stderr`，提供 `appendStdout`/`appendStderr` 变更方法
    - 提供 `stdoutText`/`stderrText` 使用 `String(decoding:as:UTF8.self)` 的有损解码视图（仅展示用）
    - `Codable, Sendable`
    - _Requirements: 1.5, 5.3_

  - [x] 1.3 实现 `OperationLogEntry` 结构与派生属性
    - 字段：id、kind、command、startedAt、finishedAt、exitCode、result、output、repoContextID
    - 派生属性：`isStreaming`、`isTerminal`
    - 实现 `Codable, Sendable, Identifiable, Equatable`
    - _Requirements: 1.1, 1.2, 1.4, 1.5_

  - [x]* 1.4 编写数据模型属性测试与非 UTF-8 边界测试
    - 在 `GitN/Tests/GitNTests/` 新增 `OperationLogEntryTests.swift`
    - **Property 4：流式增量累积与切分方式无关** — 对 `OperationOutput.appendStdout/appendStderr` 任意切分的 chunk 序列断言累积结果等于按序拼接（≥100 迭代）
    - **Property 6：非 UTF-8 字节完整保留且不丢记录** — 生成含非法 UTF-8 字节的 `Data`，断言原始字节完整保留、有损解码不崩溃（≥100 迭代）
    - 标签：`Feature: git-operation-history-logs, Property 4` / `Property 6`
    - _Requirements: 3.1, 3.2, 5.3_

- [x] 2. 实现持久化层 `OperationHistoryStore`
  - [x] 2.1 定义 `OperationHistoryStoring` 协议与 `OperationHistoryStore` 实现
    - 在 `GitN/Sources/GitN/Services/` 下新增 `OperationHistoryStore.swift`
    - 协议 `OperationHistoryStoring: Sendable`：`load() throws -> [OperationLogEntry]`、`save(_:) throws`
    - `OperationHistoryStore` 持有 per-repo `fileURL`；`save` 采用「临时文件 + 原子替换」写入，`load`/`save` 使用带 `schemaVersion` 的 JSON 包裹（`Data` 字段 base64）
    - 缺失文件 → `load()` 返回空数组；损坏/无法解析 → 抛出可识别的 decode 错误
    - 提供 `repoKey` 生成（`standardizedFileURL.resolvingSymlinksInPath().path` 的稳定哈希）与 Application Support 目录定位/创建
    - _Requirements: 2.1, 2.3, 2.4, 2.5_

  - [x]* 2.2 编写持久化 round-trip 与隔离属性测试
    - 新增 `OperationHistoryStoreTests.swift`，使用 `TemporaryGitRepository` 或临时目录
    - **Property 3：per-Repo 持久化 round-trip 与隔离** — 两个不同 Repo_Context 各写入任意事件序列后从磁盘加载，逐字段相等且互不包含对方 entry（≥100 迭代）
    - 标签：`Feature: git-operation-history-logs, Property 3`
    - _Requirements: 1.4, 2.1, 2.2, 2.3, 4.5_

  - [x]* 2.3 编写 store 缺失与损坏的边界测试
    - **EDGE_CASE 2.4**：文件缺失时 `load` 返回空历史且不报错
    - **EDGE_CASE 2.5**：注入随机非法字节，断言 `load` 抛出可识别的 decode 错误（供 service 转空历史）
    - _Requirements: 2.4, 2.5_

- [x] 3. 实现服务层 `OperationHistoryService` 与投影 `OperationHistoryState`
  - [x] 3.1 实现 `OperationHistoryState`（`@Observable` 只读投影）与视图模型
    - 在 `GitN/Sources/GitN/Models/` 下新增 `OperationHistoryState.swift`
    - 字段：`entries`、单调递增 `version`；派生 `orderedEntries`（最近在前）、`isEmpty`
    - 纯函数 `rowViewModel(for:)`（kindDisplay/startedAtDisplay/resultDisplay）与 `detailViewModel(for:)`（commandLine/exitCodeDisplay/stdoutText/stderrText），及 `HistoryRowViewModel`/`HistoryDetailViewModel` 类型
    - 内部变更入口：`apply(_:)`、`upsert(_:)`（`version` 递增）
    - _Requirements: 3.3, 4.2, 4.3, 4.4, 4.6_

  - [x] 3.2 实现 `OperationHistoryService` 记录/更新/加载/持久化编排
    - 在 `GitN/Sources/GitN/Services/` 下新增 `OperationHistoryService.swift`，标注 `@MainActor`，一个 Repo_Context 一个实例
    - `loadFromDisk()`：加载已持久化历史；缺失/损坏时以空历史初始化并记诊断日志（不崩溃）
    - `static func isMutating(_:)` 分类（仅对 Mutating_Operation 记录）
    - `beginEntry(kind:command:)` 返回 UUID；`appendOutput(_:stdout:stderr:)` 递增 `version`；`finish(_:exitCode:captured:)`；`markInterrupted(_:)`
    - 所有变更入口为 `Void` 且不 throw；每次变更后 `persist()` 后台异步落盘，失败仅记诊断日志、保留内存历史
    - 通过注入 `clock` 支持时间戳断言，通过注入 `OperationHistoryStoring` 支持失败注入
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 5.1, 5.4_

  - [x]* 3.3 编写服务层记录/完成/中断属性测试
    - 新增 `OperationHistoryServiceTests.swift`，对齐 `RepoReflogLoaderTests` 风格
    - **Property 1：变更类操作开始即被完整记录** — Mutating 记录、Read-only 不记录（≥100 迭代）
    - **Property 2：完成语义按退出码派生** — `finish` 后 exitCode/finishedAt/result 正确，覆盖捕获与流式两条路径（≥100 迭代）
    - **Property 9：中断保留已收集输出并标记中断态** — `markInterrupted` 后 result==.interrupted、保留输出（≥100 迭代）
    - 标签：`Feature: git-operation-history-logs, Property 1` / `Property 2` / `Property 9`
    - _Requirements: 1.1, 1.2, 1.3, 3.4, 5.2_

  - [x]* 3.4 编写服务层渲染字段与旁路不变量属性测试
    - **Property 7：历史渲染包含必需字段** — 行/详情视图模型包含类型、开始时间、结果、命令、退出码、完整输出（≥100 迭代）
    - **Property 10：历史按时间有序且最近可识别** — `orderedEntries` 按 startedAt 单调排序（≥100 迭代）
    - **Property 8：记录/持久化为旁路，不改变 git 结果** — 注入记录/持久化失败，断言变更入口不 throw、内存历史保留（≥100 迭代）
    - **EXAMPLE 3.3**：向进行中的 streaming entry `appendOutput`，断言 `state.version` 递增
    - **EDGE_CASE 2.5**：service 接到损坏 store 时以空历史继续并记诊断错误
    - 标签：`Feature: git-operation-history-logs, Property 7` / `Property 10` / `Property 8`
    - _Requirements: 4.2, 4.3, 4.4, 4.6, 5.1, 5.4, 2.5_

- [x] 4. Checkpoint - 确保模型/持久化/服务层测试通过
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. 实现 `GitStreamingExecutor` 流式执行路径
  - [x] 5.1 实现 `GitStreamingExecutor` 与 `GitStreamingResult`
    - 在 `GitN/Sources/GitN/Services/` 下新增 `GitStreamingExecutor.swift`
    - 基于 `FileHandle.readabilityHandler` 增量读取 stdout/stderr，串行队列同步两路回调，`terminationHandler` 排空残余并聚合返回 `GitStreamingResult(exitCode/stdout/stderr)`
    - 复用 `GitCLI.enrichedEnvironment(extra:)` 设置进程环境，使 git hook 可解析工具
    - 支持取消：`Task` 取消触发 `process.terminate()`；非零退出仍保留已累积输出；全程以 `Data` 传递不做字符串解码
    - _Requirements: 3.1, 3.2, 3.5, 3.6_

  - [x]* 5.2 编写流式执行器属性测试与装配 SMOKE
    - 新增 `GitStreamingExecutorTests.swift`，用短命 shell 命令（如分块 `printf`）验证增量累积而不依赖真实网络
    - **Property 4：流式增量累积与切分方式无关** — 通过执行器实际增量回调断言最终缓冲等于按序拼接、不丢字节（≥100 迭代）
    - **Property 5：流式失败保留全部已收集输出** — 失败前收集的输出 + 非零退出码，断言 result 语义与输出完整保留（≥100 迭代）
    - **SMOKE 3.5**：断言执行器进程环境使用 `GitCLI.enrichedEnvironment`（PATH 含 `/opt/homebrew/bin` 等）
    - 标签：`Feature: git-operation-history-logs, Property 4` / `Property 5`
    - _Requirements: 3.1, 3.2, 3.5, 3.6_

- [x] 6. `RepoViewModel` orchestration-only 接线
  - [x] 6.1 在 `RepoViewModel` 持有并加载 `OperationHistoryService`
    - 在 `init(path:name:...)` 中构造 `operationHistory`（`repoContextID = path`，注入 `OperationHistoryStore(fileURL: …repoKey…)`），与 `reflogLoader` 并列
    - 在 `loadAll()` 元数据优先阶段之后触发 `await operationHistory.loadFromDisk()`，对齐 `loadReflog()` 生命周期
    - 暴露只读 `var operationHistoryState: OperationHistoryState { operationHistory.state }`
    - _Requirements: 2.2, 1.4_

  - [x] 6.2 远程/网络类接线（Streaming）
    - 在 `performRemoteOperation(toolbarOperation:_:)` 及 push/pull/fetch 专用方法中，将实际执行替换为 `GitStreamingExecutor.stream(...)`，环绕 `beginEntry → appendOutput(Task{@MainActor}) → finish/markInterrupted`
    - 覆盖 fetch/fetchPrune/pull/pullFF/pullRebase/pullForce/push/pushForce/pushTag 全部变体
    - 保持旁路语义：记录/持久化失败不改变 git 返回或抛出结果；仅真实 exitCode 决定 throw
    - _Requirements: 1.1, 1.2, 3.1, 3.2, 3.3, 3.4, 3.6, 5.2, 5.4_

  - [x] 6.3 本地变更类接线（Captured）与 GitService 极薄 capturing 变体
    - 在 `GitService` 新增极薄的 capturing 变体（如 `mergeCapturingOutput` 等），复用现有 `cli.execute` 的 `(stdout, stderr)`；libgit2 类操作无 stdout/stderr 时 `captured` 为空但仍记录退出结果
    - 在 `performCommit/performMerge/performRebase/performCheckoutBranch/performCheckoutCommit/performReset/performStashSave` 环绕 `beginEntry → finish(captured:)`，失败路径记录非零退出码与捕获输出后重新抛出
    - _Requirements: 1.1, 1.2, 1.5, 5.4_

  - [x]* 6.4 编写接线集成测试（hook 输出）
    - 新增 `OperationHistoryIntegrationTests.swift`，使用带 `pre-push` hook 的 `TemporaryGitRepository`
    - **INTEGRATION 3.2**：执行一次 push，断言对应 entry 输出包含 hook 打印内容（1–2 例）
    - _Requirements: 3.1, 3.2, 1.2_

- [x] 7. Checkpoint - 确保执行器与接线测试通过
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. 工具栏与 `HistoryView` UI 接入
  - [x] 8.1 实现 `HistoryView` 浮层界面
    - 在 `GitN/Sources/GitN/Views/` 下新增 `HistoryView.swift`，绑定当前 `RepoViewModel.operationHistoryState`
    - 列表按 `orderedEntries` 展示（类型、开始时间、结果）；展开显示命令、退出码、完整 stdout/stderr；随 `state.version` 实时刷新进行中的 streaming entry
    - 空历史显示空状态提示
    - _Requirements: 4.2, 4.3, 4.4, 4.6, 3.3_

  - [x] 8.2 在 `RepoContainerView` 工具栏新增历史入口
    - 在 fetch/pull/push 工具栏区新增「历史」按钮（`clock.arrow.circlepath` 类图标），沿用共享 `hoverTooltip(...)` 与既有 chrome/按钮语言
    - 点击以 `popover`（或 `sheet`）打开 `HistoryView`；切换标签页时绑定当前 Repo_Context，仅显示当前仓库历史
    - _Requirements: 4.1, 4.5_

  - [x]* 8.3 空状态与入口可用性校验（快照/手动）
    - **EXAMPLE 4.1 / 4.6**：工具栏入口存在且可打开 `History_View`；空历史时视图模型返回空状态表示
    - _Requirements: 4.1, 4.6_

- [x] 9. Final checkpoint - 确保全部测试通过
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- 标记 `*` 的子任务为可选（测试类与 UI 校验类），可为更快 MVP 跳过；核心实现任务不标记为可选。
- 每个任务引用具体需求条款以保证可追溯性。
- 属性测试 ≥100 迭代，统一打标签 `Feature: git-operation-history-logs, Property {n}`，测试风格对齐 `RepoReflogLoaderTests` 与 `TemporaryGitRepository`。
- 记录层为旁路副作用：service 变更入口不 throw，异常转诊断日志，保证 git 编排结果与「未记录」时一致（Property 8）。
- 按 `AGENTS.md`：新增逻辑落在聚焦、可单测的服务/模型/执行器层，`RepoViewModel` 保持 orchestration-only，`GitService` 仅做极薄 capturing 扩展；跨切面改动实现前应先撰写 RFC（本设计文档可作技术底稿）。

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3"] },
    { "id": 2, "tasks": ["1.4", "2.1", "3.1", "5.1"] },
    { "id": 3, "tasks": ["2.2", "2.3", "3.2", "5.2", "8.1"] },
    { "id": 4, "tasks": ["3.3", "3.4", "6.1", "8.2"] },
    { "id": 5, "tasks": ["6.2", "6.3", "8.3"] },
    { "id": 6, "tasks": ["6.4"] }
  ]
}
```
