# Design Document — Git 操作历史日志（git-operation-history-logs）
# Design Document — Git 操作历史日志（git-operation-history-logs）

## Overview

本设计为 GitN 引入「Git 操作历史日志」功能：为每个仓库（每个标签页 / `Repo_Context`）记录所有会修改仓库状态的 git 操作，持久化到磁盘并在重启后恢复；对 push/pull/fetch 类操作实时流式展示进程与 git hook 输出；并通过工具栏附近的浮层界面（`History_View`）展示可展开查看的历史列表。

设计遵循仓库 `AGENTS.md` 的既有分层约束：

- 新增聚焦、可单元测试的服务层 `OperationHistoryService`（服务）+ `OperationHistoryState`/`OperationLogEntry`（模型），对齐 `RepoReflogLoader`（服务）+ `RepoReflogState`（模型）的既有模式。
- 不把 provider/网络/流式细节堆进 `RepoViewModel`，也不把历史记录职责堆进 `GitService`。`RepoViewModel` 仅做编排（orchestration-only）的最小接线。
- 在 `GitCLI` 中新增聚焦的**流式执行路径**（`GitStreamingExecutor`），基于 `FileHandle.readabilityHandler` 增量读取，复用 `GitCLI.enrichedEnvironment` 使 git hook 能解析工具（如 `git-lfs pre-push`）。当前 `GitCLI.execute` 用 `readDataToEndOfFile()` + `waitUntilExit()` 全量缓冲，无法满足实时流式需求。

> **流程说明（RFC 要求）**：按 `AGENTS.md`「Testing And Documentation Obligations」，本变更属于**跨切面改动**——新增服务层组件、在 `GitCLI` 增加新的执行路径、并在 `RepoViewModel` 的远程/本地变更编排流程中接线。因此在实现前应先撰写一份 RFC（见 `docs/ENGINEERING_WORKFLOW.md` 与 `docs/templates/feature-intake-template.md`），说明为何流式执行器落在 `GitCLI` 邻域、为何历史记录落在独立服务层、以及 `RepoViewModel` 接线为何保持 orchestration-only。本设计文档可作为该 RFC 的技术底稿。

### 与现有代码的锚点

- 服务/模型模式：`GitN/Sources/GitN/Services/RepoReflogLoader.swift` + `GitN/Sources/GitN/Models/RepoReflogState.swift`。
- 执行路径：`GitN/Sources/GitN/Services/GitCLI.swift` 的 `execute(...)` 与 `enrichedEnvironment(extra:)`。
- 远程编排：`RepoViewModel.performFetch/performPull/performPush/...` → `performRemoteOperation(toolbarOperation:_:)`。
- 本地变更编排：`performCommit`、`performMerge`、`performRebase`、`performCheckoutBranch/Commit`、`performReset`、`performStashSave/...`。
- 工具栏入口：`GitN/Sources/GitN/Views/RepoContainerView.swift` 中 fetch/pull/push 的工具栏按钮区域。
- 加载时机：`RepoViewModel.loadAll()`（元数据优先，随后 reflog），历史加载对齐同一生命周期。

## Non-Goals

- 不记录 `Read_Only_Operation`（log/status/diff 等只读查询）。
- 不改变底层 git 操作的语义或返回结果；历史记录纯属旁路副作用。
- 不做跨仓库聚合视图、搜索、导出、日志轮转/清理策略（可作为后续增强）。
- 不实现远程/网络之外的实时流式（仅 push/pull/fetch 及其 force/prune/tag 变体走流式，其余变更类在完成时记录捕获输出）。
- 不改动 `GitService` 现有 fetch/pull/push 的 libgit2/CLI 选择策略。

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI 层 (SwiftUI)                                                      │
│                                                                       │
│  RepoContainerView (toolbar: fetch/pull/push)                         │
│     └── HistoryToolbarButton ──(popover/sheet)──> HistoryView         │
│                                     │                                 │
│                                     ▼                                 │
│              OperationHistoryState (@Observable, 只读投影)            │
└─────────────────────────────────────┬────────────────────────────────┘
                                       │ 观察 / 触发
┌──────────────────────────────────────▼───────────────────────────────┐
│  编排层                                                                │
│  RepoViewModel (orchestration-only 最小接线)                           │
│   - performRemoteOperation / performCommit / performMerge / ...        │
│   - 持有 per-repo 的 OperationHistoryService                           │
└───────────┬───────────────────────────────────────────┬──────────────┘
            │ 记录变更类操作                              │ 流式执行 push/pull/fetch
┌───────────▼───────────────────────┐        ┌───────────▼──────────────┐
│  OperationHistoryService (服务)    │        │  GitStreamingExecutor     │
│   - beginEntry / appendOutput /    │        │  (GitCLI 邻域聚焦助手)    │
│     finish / markInterrupted       │◀───────│  FileHandle               │
│   - 内存状态 + 持久化编排           │ 增量回传 │  .readabilityHandler      │
│   - 分类 (isMutating / isStreaming) │        │  + enrichedEnvironment     │
└───────────┬───────────────────────┘        └───────────────────────────┘
            │ 落盘 / 加载
┌───────────▼───────────────────────┐
│  OperationHistoryStore (持久化)    │
│   - per-Repo JSON 文件              │
│   - load / save / 损坏处理          │
└─────────────────────────────────────┘
```

### 分层职责与边界

- **`OperationLogEntry`（模型，纯数据）**：一条操作历史记录，可 `Codable`、`Sendable`、`Identifiable`。包含类型、命令、时间戳、退出码、结果、输出（原始字节 + 有损解码视图）、流式/中断标记。无 I/O、无 UI 依赖。
- **`OperationHistoryState`（模型，`@Observable`）**：单个 `Repo_Context` 的内存历史投影，供 UI 观察与排序/格式化查询。承担纯展示派生逻辑（排序、行/详情视图模型），不做 I/O。对齐 `RepoReflogState` 的“纯派生”定位。
- **`OperationHistoryService`（服务）**：记录、更新、查询、持久化编排的聚焦服务，一个 `Repo_Context` 一个实例。提供 `beginEntry`、`appendOutput`、`finish`、`markInterrupted`，并负责调用 store 落盘。分类函数 `isMutating`/`isStreaming` 定义记录边界。对齐 `RepoReflogLoader` 的定位。
- **`OperationHistoryStore`（持久化）**：负责 per-repo JSON 文件的 `load`/`save` 与损坏/缺失处理。可注入（协议）以便测试与失败注入。
- **`GitStreamingExecutor`（GitCLI 邻域）**：流式执行 push/pull/fetch，增量回传 stdout/stderr（含 hook 输出），复用 `GitCLI.enrichedEnvironment`。不承担历史记录职责，只通过回调把增量输出交回 service。

> 边界原则：`GitService` 不新增历史/流式职责；`RepoViewModel` 不新增流式细节，只在既有 perform* 编排里插入“begin → (append) → finish/interrupted”的最小调用。

## Components and Interfaces

以下接口以 Swift 表达（与仓库语言一致）。字段/签名为设计意图，实现时可微调。

### OperationLogEntry（数据模型）

```swift
enum GitOperationKind: String, Codable, Sendable {
    // Streaming（远程/网络类）
    case fetch, fetchPrune, pull, pullFF, pullRebase, pullForce
    case push, pushForce, pushTag
    // 本地变更类（完成时记录捕获输出）
    case commit, merge, rebase, checkout, reset, stash

    var isStreaming: Bool {
        switch self {
        case .fetch, .fetchPrune, .pull, .pullFF, .pullRebase, .pullForce,
             .push, .pushForce, .pushTag:
            return true
        default:
            return false
        }
    }
}

enum OperationResult: String, Codable, Sendable {
    case running        // 进行中（尚未完成）
    case success        // 退出码 == 0
    case failure        // 退出码 != 0
    case interrupted    // 进程被终止/中断（5.2）
}

/// 输出以原始字节存储，避免非 UTF-8 丢失（5.3）。
struct OperationOutput: Codable, Sendable {
    private(set) var stdout: Data
    private(set) var stderr: Data

    /// 有损解码视图，仅用于展示；保留可解码部分，非法字节以替换符呈现。
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    mutating func appendStdout(_ chunk: Data) { stdout.append(chunk) }
    mutating func appendStderr(_ chunk: Data) { stderr.append(chunk) }
}

struct OperationLogEntry: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let kind: GitOperationKind
    /// 完整可读命令（含 "git" 前缀与全部参数），用于展开视图展示。
    let command: [String]
    let startedAt: Date
    private(set) var finishedAt: Date?
    private(set) var exitCode: Int32?
    private(set) var result: OperationResult
    private(set) var output: OperationOutput
    /// entry 归属的 Repo_Context 标识（用于校验/隔离）。
    let repoContextID: String

    var isStreaming: Bool { kind.isStreaming }
    var isTerminal: Bool { result != .running }
}
```

### OperationHistoryState（`@Observable` 只读投影）

```swift
@Observable
final class OperationHistoryState {
    private(set) var entries: [OperationLogEntry] = []
    /// 单调递增版本号，供 UI 感知流式增量刷新（3.3）。
    private(set) var version: Int = 0

    /// 按开始时间排序（最近在前），最近操作可识别（4.3）。
    var orderedEntries: [OperationLogEntry] {
        entries.sorted { $0.startedAt > $1.startedAt }
    }

    var isEmpty: Bool { entries.isEmpty }   // 空状态（4.6）

    // 视图模型映射（4.2 / 4.4），纯函数、可单测：
    func rowViewModel(for entry: OperationLogEntry) -> HistoryRowViewModel
    func detailViewModel(for entry: OperationLogEntry) -> HistoryDetailViewModel

    // 由 service 在主线程调用的内部变更入口：
    func apply(_ entries: [OperationLogEntry])
    func upsert(_ entry: OperationLogEntry)
}
```

`HistoryRowViewModel` 至少含：`kindDisplay`、`startedAtDisplay`、`resultDisplay`。
`HistoryDetailViewModel` 至少含：`commandLine`、`exitCodeDisplay`、`stdoutText`、`stderrText`。

### OperationHistoryService（服务）

```swift
/// 每个 Repo_Context 一个实例。所有对外变更入口在 MainActor 上更新 state，
/// 持久化在后台执行。记录/持久化失败绝不向上抛给 git 编排（5.4）。
@MainActor
final class OperationHistoryService {
    let repoContextID: String
    let state: OperationHistoryState
    private let store: OperationHistoryStoring
    private let clock: () -> Date

    init(repoContextID: String,
         store: OperationHistoryStoring,
         clock: @escaping () -> Date = Date.init)

    /// 打开仓库时加载已持久化历史（2.2）；缺失/损坏时以空历史初始化（2.4/2.5）。
    func loadFromDisk() async

    /// 分类：仅对 Mutating_Operation 记录（1.3）。
    static func isMutating(_ kind: GitOperationKind) -> Bool

    /// 开始一条记录，返回 entry id（1.1）。
    @discardableResult
    func beginEntry(kind: GitOperationKind, command: [String]) -> UUID

    /// 流式增量追加（3.1/3.2）。触发 state.version 递增以驱动 UI 刷新（3.3）。
    func appendOutput(_ id: UUID, stdout: Data?, stderr: Data?)

    /// 完成：记录 finishedAt/exitCode/result（1.2/3.4），本地变更类在此传入捕获输出（1.5）。
    func finish(_ id: UUID, exitCode: Int32, captured: OperationOutput?)

    /// 中断标记：保留已收集输出（5.2）。
    func markInterrupted(_ id: UUID)

    // 每次变更后异步持久化（2.1）；失败仅记诊断日志，保留内存历史（5.1）。
    private func persist()
}
```

### OperationHistoryStore（持久化）

```swift
protocol OperationHistoryStoring: Sendable {
    func load() throws -> [OperationLogEntry]
    func save(_ entries: [OperationLogEntry]) throws
}

struct OperationHistoryStore: OperationHistoryStoring {
    let fileURL: URL   // per-repo JSON 文件

    /// 缺失文件 → 返回空（2.4）；损坏/无法解析 → 抛 decodeFailed（由 service 转空历史 + 诊断）（2.5）。
    func load() throws -> [OperationLogEntry]
    func save(_ entries: [OperationLogEntry]) throws
}
```

### GitStreamingExecutor（GitCLI 邻域聚焦助手）

```swift
struct GitStreamingResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

struct GitStreamingExecutor: Sendable {
    let repoPath: String

    /// 增量执行 git，边运行边通过回调回传 stdout/stderr chunk。
    /// - onOutput: 在后台串行队列调用，调用方负责跳回 MainActor 更新 state。
    /// - 复用 GitCLI.enrichedEnvironment 保证 hook 可解析工具（3.5）。
    /// - 支持取消/中断：cancellation 触发进程终止（5.2）。
    func stream(
        _ args: [String],
        env: [String: String]? = nil,
        onOutput: @escaping (_ stdout: Data?, _ stderr: Data?) -> Void
    ) async throws -> GitStreamingResult
}
```

## 流式执行器设计（Streaming Executor）

当前 `GitCLI.execute` 的关键行为（见 `GitCLI.swift`）：

```swift
let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile() // 全量阻塞读
let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

这会在进程结束前一直阻塞、无法边跑边回传，因此无法满足 push/pull/fetch 的实时展示。`GitStreamingExecutor` 采用 `FileHandle.readabilityHandler` 增量读取：

```swift
func stream(_ args: [String], env: [String: String]?,
            onOutput: @escaping (Data?, Data?) -> Void) async throws -> GitStreamingResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            // 关键：复用 enrichedEnvironment，使 git-lfs 等 hook 工具可被解析（3.5）
            process.environment = GitCLI.enrichedEnvironment(extra: env)

            let outPipe = Pipe(); let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            var outBuf = Data(); var errBuf = Data()
            let sync = DispatchQueue(label: "com.gitn.opstream")  // 串行化两路回调，避免竞态

            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                sync.async { outBuf.append(d); onOutput(d, nil) }   // 增量回传（3.1）
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                sync.async { errBuf.append(d); onOutput(nil, d) }   // hook 输出走 stderr（3.2）
            }

            process.terminationHandler = { proc in
                // 清理 handler，排空残余，返回聚合结果
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                sync.async {
                    if !restOut.isEmpty { outBuf.append(restOut); onOutput(restOut, nil) }
                    if !restErr.isEmpty { errBuf.append(restErr); onOutput(nil, restErr) }
                    sync.sync {} // barrier: 确保所有回调已入队
                    continuation.resume(returning: GitStreamingResult(
                        exitCode: proc.terminationStatus, stdout: outBuf, stderr: errBuf))
                }
            }

            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }
}
```

要点：

- **增量语义（3.1/3.2）**：hook 通常向 stderr 写，git progress 也多在 stderr；两路都逐 chunk 回传。累积结果与切分方式无关（结合律），见 Property 4。
- **环境（3.5）**：始终 `GitCLI.enrichedEnvironment(extra:)`，与现有 `execute` 一致，保证 `git-lfs pre-push` 等 hook 找到工具。
- **中断（5.2）**：`Task` 取消时调用 `process.terminate()`；`terminationHandler` 仍会触发，service 侧据 `exitCode`/取消标记决定 `finish(failure)` 或 `markInterrupted`。
- **失败保留输出（3.6）**：非零退出时 `GitStreamingResult` 仍带已累积 stdout/stderr，service 完成 entry 时保留。
- **非 UTF-8（5.3）**：executor 全程以 `Data` 传递，不在此层做字符串解码；解码只发生在展示层（有损）。

## Threading / Concurrency（SwiftUI 实时更新）

- `OperationHistoryService` 标注 `@MainActor`，`OperationHistoryState`（`@Observable`）的所有变更都在主线程发生，SwiftUI 观察安全。
- `GitStreamingExecutor` 在后台队列跑进程，`onOutput` 在后台串行队列回调；`RepoViewModel` 在回调里 `Task { @MainActor in service.appendOutput(...) }` 跳回主线程更新 state。
- `state.version` 单调递增，展开中的 streaming entry 视图观察它以实时刷新（3.3）。为避免高频 append 造成 UI 抖动，`appendOutput` 可做轻量合帧（如按 ~50ms 或按累计字节数节流），但每个 chunk 的字节都必须进入 `output`（不丢字节）。
- 持久化 `persist()` 用后台任务/串行队列写文件，避免阻塞主线程；写入采用“临时文件 + 原子替换”减少半写风险。

## Data Model — OperationLogEntry 细节

- **streaming vs captured 输出**：两种来源统一存入同一 `OperationOutput`（`stdout`/`stderr` 均为 `Data`）。
  - Streaming 操作：运行期间由 `appendOutput` 增量填充。
  - 本地变更类：`finish(captured:)` 一次性写入捕获输出（1.5）。
- **interrupted 状态**：`result == .interrupted`，`finishedAt` 记录中断时刻，`output` 保留已收集内容，`exitCode` 可为 nil（进程被杀）。
- **非 UTF-8 处理**：以字节（`Data`）为权威存储，`stdoutText/stderrText` 用 `String(decoding:as:UTF8.self)` 做**有损**解码用于展示；持久化时 `Data` 经 JSON（base64）编码，round-trip 后字节完全一致（见 Property 6）。

## Persistence — 格式与位置

- **位置**：`Application Support/GitN/OperationHistory/<repoKey>.json`。
  - `repoKey` 由 `repoPath` 标准化后（`standardizedFileURL.resolvingSymlinksInPath().path`）取稳定哈希（如 SHA-256 十六进制），避免路径中的非法文件名字符，并与现有以 `repoPath` 作为 key 的约定（`UserDefaults "GitN.*.\(repoPath)"`）语义一致。
  - `Application Support` 通过 `FileManager.default.url(for: .applicationSupportDirectory, ...)` 获取；目录不存在则创建。
- **格式**：`Codable` 的 `[OperationLogEntry]` 顶层数组，JSON，`Data` 字段以 base64 编码（Foundation 默认）。带一个 `schemaVersion` 包裹便于演进：

```json
{ "schemaVersion": 1, "entries": [ { "id": "…", "kind": "push", "command": ["git","push"], "startedAt": "…", "result": "success", "exitCode": 0, "output": { "stdout": "<base64>", "stderr": "<base64>" }, "repoContextID": "…" } ] }
```

- **per-Repo 隔离（2.3）**：不同 `repoKey` → 不同文件，互不混合。
- **缺失（2.4）**：文件不存在 → `load()` 返回空数组、不报错。
- **损坏（2.5）**：解析失败 → service 捕获后以空历史继续，并记录可诊断错误（日志），不崩溃。
- **写失败（5.1）**：`save` 抛错 → service 保留内存历史 + 记诊断日志，不向 git 编排传播。

## Integration Points（RepoViewModel / GitService）

原则：**orchestration-only**，`GitService` 不改职责，`RepoViewModel` 只做最小接线。

### RepoViewModel 生命周期接线

- **持有**：`RepoViewModel` 新增 `private let operationHistory: OperationHistoryService`，在 `init(path:name:...)` 中构造（`repoContextID = path`，`store = OperationHistoryStore(fileURL: …repoKey…)`），与 `reflogLoader` 并列。
- **加载（2.2）**：在 `loadAll()` 的“元数据优先”阶段之后触发 `await operationHistory.loadFromDisk()`，与 `loadReflog()` 生命周期对齐。
- **UI 访问**：暴露只读 `var operationHistoryState: OperationHistoryState { operationHistory.state }` 供 `HistoryView` 观察。

### 远程/网络类接线（Streaming）

改造集中在 `performRemoteOperation(toolbarOperation:_:)` 与 push/pull 的专用方法。将 `GitService.fetch/pull/push` 的实际执行替换为经 `GitStreamingExecutor` 的流式执行，并环绕 begin/append/finish：

```swift
// 编排层伪代码（RepoViewModel 内）
func recordStreaming(kind: GitOperationKind, args: [String]) async throws {
    let id = operationHistory.beginEntry(kind: kind, command: ["git"] + args)   // 1.1
    do {
        let result = try await GitStreamingExecutor(repoPath: repoPath).stream(args) { out, err in
            Task { @MainActor in operationHistory.appendOutput(id, stdout: out, stderr: err) } // 3.1/3.2/3.3
        }
        operationHistory.finish(id, exitCode: result.exitCode,
                                captured: OperationOutput(stdout: result.stdout, stderr: result.stderr)) // 3.4/3.6
        if result.exitCode != 0 { throw GitError.operationFailed(String(decoding: result.stderr, as: UTF8.self)) }
    } catch is CancellationError {
        operationHistory.markInterrupted(id)   // 5.2
        throw CancellationError()
    }
}
```

- push/pull/fetch（含 force/prune/tag 变体）改为调用该流式路径；其余 `performRemoteOperation` 使用者（如 `stashSave`、`resetToCommit`、`checkout`）走本地变更类捕获路径。
- **非侵入（5.4）**：`recordStreaming` 内的记录/持久化失败不改变 git 结果——记录副作用被 service 内部吞掉，只有 git 的真实 exitCode 决定 throw。为保证这一点，编排层用 `finish/append/markInterrupted` 均为 `Void` 且不 throw。

### 本地变更类接线（Captured）

`performCommit/performMerge/performRebase/performCheckoutBranch/performCheckoutCommit/performReset/performStashSave` 等：

```swift
let id = operationHistory.beginEntry(kind: .commit, command: ["git","commit","-m", msg]) // 1.1
do {
    let captured = try await git.commitCapturingOutput(message: msg)   // 见下
    operationHistory.finish(id, exitCode: 0, captured: captured)       // 1.2/1.5
} catch {
    operationHistory.finish(id, exitCode: nonZeroCode(from: error),
                            captured: capturedOutput(from: error))     // 1.2
    throw error
}
```

- 现状：部分本地变更走 libgit2（如 `commit`、`resetToCommit`、`stashSave`），无 stdout/stderr；部分走 CLI（`merge`、`rebase` 经 `runGit`）。
- **GitService 边界**：不在 `GitService` 里堆历史逻辑。为拿到 CLI 变更类的捕获输出，`GitService` 仅新增**极薄**的“capturing”变体（如 `mergeCapturingOutput`），复用现有 `cli.execute` 返回的 `(stdout, stderr)`；libgit2 类操作无 stdout/stderr 时 `captured` 为空但仍记录退出结果。这属于既有 CLI 执行的自然扩展，不是新增网络/hosted/auth 职责，未触碰受保护 hotspot 的语义。

### 工具栏与 History_View（UI）

- 在 `RepoContainerView.swift` 的 fetch/pull/push 工具栏区新增一个「历史」按钮（`clock.arrow.circlepath` 类图标），沿用 `hoverTooltip(...)` 与既有 chrome/按钮语言（`AGENTS.md` UI 约束）。
- 点击以 `popover`（或 `sheet`）打开 `HistoryView`，展示 `operationHistoryState.orderedEntries`：
  - 列表项：类型、开始时间、结果（4.2/4.3）。
  - 展开项：命令、退出码、完整 stdout/stderr（4.4），streaming 进行中随 `state.version` 实时刷新（3.3）。
  - 空历史显示空状态提示（4.6）。
- 切换标签页时，`HistoryView` 绑定当前 `RepoViewModel` 的 `operationHistoryState`，因此仅显示当前 `Repo_Context` 历史（4.5）。

## Error Handling

| 场景 | 处理 | 关联 AC |
| --- | --- | --- |
| store 文件缺失 | `load()` 返回空数组，不报错 | 2.4 |
| store 数据损坏 | service 转为空历史，记诊断日志，继续运行 | 2.5 |
| 持久化写入失败 | 保留内存历史，记诊断日志，不影响 git | 5.1 / 5.4 |
| 进程被终止/中断 | `markInterrupted`，保留已收集输出 | 5.2 |
| 非 UTF-8 输出 | 以 `Data` 权威存储，展示层有损解码，不丢记录 | 5.3 |
| 流式操作失败 | 保留已收集输出 + 记 `failure` + exitCode | 3.6 |
| 记录/持久化任何失败 | 绝不改变或阻断底层 git 操作结果 | 5.4 |

关键不变量：**记录层是旁路**。所有 service 变更入口不 throw，异常在 service 内部转为诊断日志，从而保证 git 编排的返回/抛出与“未记录”时一致（Property 8）。

## Testing Strategy（非 UI 服务层）

对齐 `RepoReflogLoaderTests`/`RepoReflogStateTests` 的既有测试风格与 `TemporaryGitRepository` 工具。

- **单元测试（示例/边界/错误）**：
  - 分类边界（1.3）：Mutating vs Read-only 是否记录。
  - store 缺失（2.4）/损坏（2.5）：注入空目录与随机非法字节。
  - 空状态视图模型（4.6）。
  - 装配检查（3.5，SMOKE）：streaming executor 环境含 enriched PATH。
- **集成测试（1-3 例）**：
  - hook 输出（3.2）：带 `pre-push` hook 的临时仓库跑一次 push，断言 entry 含 hook 打印内容。
- **属性测试（≥100 迭代，使用 SwiftCheck 或等价随机生成；每条对应设计属性）**：
  - 记录/完成语义、隔离、持久化 round-trip、增量累积结合律、失败/中断保留输出、非侵入不变量、渲染信息完整、非 UTF-8 保留。
- **可测边界**：service/store/state/executor 均不依赖 SwiftUI；`OperationHistoryStore` 用可注入协议 `OperationHistoryStoring` 支持失败注入；`clock` 可注入以断言时间戳。执行器可用注入的“假数据源/假进程”或短命 shell 命令（如 `printf` 分块）验证增量累积而不依赖真实网络。
- 每条属性测试打标签：**Feature: git-operation-history-logs, Property {number}: {property_text}**。

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

**属性反思（去冗余）**：`1.4`（归属 Repo_Context）、`2.2`（打开时加载可查询）、`4.5`（切换标签仅显示当前）本质都是「per-Repo 隔离 + 持久化 round-trip」，合并为 Property 3；`1.2`（完成语义）与 `3.4`（流式完成）合并为 Property 2（同时覆盖捕获与流式两条路径）；`4.2`（列表项字段）与 `4.4`（详情字段）合并为 Property 7（渲染必需字段完整）；`3.6`（失败保留输出）与 `5.2`（中断保留输出）保持独立，因终态结果不同（failure vs interrupted）。

### Property 1: 变更类操作开始即被完整记录

*For any* `Mutating_Operation`（任意操作类型与命令参数），`beginEntry` 之后历史中应存在一条对应 entry，其 `kind`、`command`、`repoContextID` 与输入一致、`startedAt` 非空、`result == .running`，且历史长度恰好增加一；*for any* `Read_Only_Operation`，历史长度不变。

**Validates: Requirements 1.1, 1.3**

### Property 2: 完成语义按退出码派生（覆盖捕获与流式）

*For any* 已开始的 entry 与任意退出码 `c`，`finish(exitCode: c, captured:)` 之后该 entry 的 `exitCode == c`、`finishedAt >= startedAt`、且 `result == (c == 0 ? .success : .failure)`；该性质对本地变更类（一次性捕获）与 streaming 类（增量后完成）两条路径均成立。

**Validates: Requirements 1.2, 3.4**

### Property 3: per-Repo 持久化 round-trip 与隔离

*For any* 两个不同的 `Repo_Context` 及各自任意的操作事件序列，将每个上下文的历史写入其 `History_Store` 后再从磁盘加载，得到的历史应与该上下文的内存历史逐字段相等，且任一上下文的加载结果不包含另一上下文的任何 entry。

**Validates: Requirements 1.4, 2.1, 2.2, 2.3, 4.5**

### Property 4: 流式增量累积与切分方式无关

*For any* 字节输出流被任意方式切分成的 chunk 序列，`appendOutput` 顺序累积后的最终 `stdout`/`stderr` 缓冲应等于按序拼接的全部 chunk（结合律），与切分粒度无关，且不丢失任何字节。

**Validates: Requirements 3.1, 3.2**

### Property 5: 流式失败保留全部已收集输出

*For any* 在失败前已收集的输出与任意非零退出码，流式完成后对应 entry 的 `result == .failure`、保留 `exitCode`，且其 `output` 完整包含失败前收集到的全部字节。

**Validates: Requirements 3.6**

### Property 6: 非 UTF-8 字节完整保留且不丢记录

*For any* 包含非法 UTF-8 字节的输出，完成该 entry 后其原始字节（`Data`）被完整保留（持久化 round-trip 后逐字节一致），展示层有损解码不崩溃，且 entry 被标记为终态（不丢失记录）。

**Validates: Requirements 5.3**

### Property 7: 历史渲染包含必需字段

*For any* entry，其行视图模型应包含操作类型、开始时间与成功/失败结果；其详情视图模型应包含完整 git 命令、退出状态码以及捕获或流式收集到的完整输出。

**Validates: Requirements 4.2, 4.4**

### Property 8: 记录/持久化为旁路，不改变 git 结果

*For any* 底层 git 操作结果（成功或失败）与任意注入的记录/持久化失败，经历史记录包装后向调用方返回或抛出的结果，应与不进行任何历史记录时的底层结果完全一致。

**Validates: Requirements 5.1, 5.4**

### Property 9: 中断保留已收集输出并标记中断态

*For any* 中断前已收集的输出，`markInterrupted` 之后对应 entry 的 `result == .interrupted`，记录 `finishedAt`，且 `output` 完整保留中断前收集到的全部字节。

**Validates: Requirements 5.2**

### Property 10: 历史按时间有序且最近可识别

*For any* entry 集合，`orderedEntries` 应按 `startedAt` 单调排序（约定最近在前），使最近的操作可被稳定识别。

**Validates: Requirements 4.3**

---

### 非属性型验证（示例 / 边界 / 集成 / 装配）

- **EDGE_CASE 2.4**：`History_Store` 文件缺失时 `load` 返回空历史且不报错。
- **EDGE_CASE 2.5**：`History_Store` 含随机非法字节时 service 以空历史继续并记录可诊断错误，不崩溃。
- **EXAMPLE 3.3**：向进行中的 streaming entry `appendOutput`，断言 `state.version` 递增（驱动 UI 实时刷新）；视图实时刷新本身由手动/快照验证。
- **INTEGRATION 3.2（hook）**：带 `pre-push` hook 的临时仓库执行一次 push，断言 entry 输出包含 hook 打印内容（1–2 例）。
- **SMOKE 3.5**：断言 `GitStreamingExecutor` 启动进程时环境使用 `GitCLI.enrichedEnvironment`（PATH 含 `/opt/homebrew/bin` 等）。
- **EXAMPLE 4.1 / 4.6**：工具栏入口存在且可打开 `History_View`（手动/快照）；空历史时视图模型返回空状态表示。
