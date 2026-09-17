import Foundation

// MARK: - GitOperationKind

/// 一条 Git 操作历史记录的类型。分为「流式（远程/网络类）」与「本地变更类」两组。
enum GitOperationKind: String, Codable, Sendable {
    // Streaming（远程/网络类）
    case fetch, fetchPrune, pull, pullFF, pullRebase, pullForce
    case push, pushForce, pushTag
    // 本地变更类（完成时记录捕获输出）
    case commit, merge, rebase, checkout, reset, stash

    /// 是否为流式（远程/网络类）操作，运行期间通过增量回调填充输出。
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

// MARK: - OperationResult

/// 一条操作记录的结果状态。
enum OperationResult: String, Codable, Sendable {
    case running        // 进行中（尚未完成）
    case success        // 退出码 == 0
    case failure        // 退出码 != 0
    case interrupted    // 进程被终止/中断（5.2）
}

// MARK: - OperationOutput

/// 输出以原始字节存储，避免非 UTF-8 丢失（5.3）。
///
/// 以 `Data` 为权威存储，`stdout`/`stderr` 仅通过 `appendStdout`/`appendStderr`
/// 变更方法追加字节，保证流式增量累积与切分方式无关。展示层使用
/// `stdoutText`/`stderrText` 做有损 UTF-8 解码，非法字节以替换符呈现。
struct OperationOutput: Codable, Sendable, Equatable {
    private(set) var stdout: Data
    private(set) var stderr: Data

    init(stdout: Data = Data(), stderr: Data = Data()) {
        self.stdout = stdout
        self.stderr = stderr
    }

    /// 有损解码视图，仅用于展示；保留可解码部分，非法字节以替换符呈现。
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    mutating func appendStdout(_ chunk: Data) { stdout.append(chunk) }
    mutating func appendStderr(_ chunk: Data) { stderr.append(chunk) }
}
// MARK: - OperationLogEntry

/// 一条 Git 操作历史记录（纯数据模型，无 I/O、无 UI 依赖）。
///
/// 记录一次会修改仓库状态的 git 操作：类型、完整命令、时间戳、退出码、结果、
/// 输出（原始字节 + 有损解码视图）以及归属的 `Repo_Context` 标识。
/// 可 `Codable`/`Sendable` 以支持 per-Repo 持久化 round-trip，可 `Identifiable`
/// 供 UI 列表使用，`Equatable` 便于测试逐字段断言。
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

    /// 是否为流式（远程/网络类）操作。派生自 `kind`。
    var isStreaming: Bool { kind.isStreaming }

    /// 是否已到达终态（非进行中）。
    var isTerminal: Bool { result != .running }

    /// memberwise init，适用于 `beginEntry` 场景：默认开始一条进行中的记录
    /// （`result == .running`，`finishedAt`/`exitCode` 为空，`output` 为空缓冲）。
    init(
        id: UUID = UUID(),
        kind: GitOperationKind,
        command: [String],
        startedAt: Date,
        finishedAt: Date? = nil,
        exitCode: Int32? = nil,
        result: OperationResult = .running,
        output: OperationOutput = OperationOutput(),
        repoContextID: String
    ) {
        self.id = id
        self.kind = kind
        self.command = command
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.result = result
        self.output = output
        self.repoContextID = repoContextID
    }

    // MARK: - 内部变更助手（纯数据，无 I/O）
    //
    // `finishedAt`/`exitCode`/`result`/`output` 为 `private(set)`，仅通过以下受控
    // 变更方法修改，保证状态转移语义集中在模型内、便于单测，且不泄漏可写字段。

    /// 增量追加流式输出（3.1/3.2）。任意切分的 chunk 顺序累积等价于按序拼接（Property 4）。
    mutating func appendOutput(stdout: Data?, stderr: Data?) {
        if let stdout, !stdout.isEmpty { output.appendStdout(stdout) }
        if let stderr, !stderr.isEmpty { output.appendStderr(stderr) }
    }

    /// 完成一条记录（1.2/3.4）：记录退出码、完成时间，并按退出码派生成功/失败结果。
    /// 若传入 `captured` 输出（本地变更类一次性捕获，1.5），则替换当前输出缓冲。
    mutating func finish(at date: Date, exitCode: Int32, captured: OperationOutput?) {
        self.finishedAt = date
        self.exitCode = exitCode
        self.result = (exitCode == 0) ? .success : .failure
        if let captured { self.output = captured }
    }

    /// 标记为中断态（5.2）：保留已收集输出，记录中断时刻；`exitCode` 保持为空。
    mutating func markInterrupted(at date: Date) {
        self.finishedAt = date
        self.result = .interrupted
    }
}
