import Foundation

// MARK: - OperationHistoryService

/// 单个 `Repo_Context` 的操作历史记录/更新/加载/持久化编排服务（聚焦服务层，非 UI）。
///
/// 每个 `Repo_Context` 一个实例，对齐 `RepoReflogLoader` 的定位。所有对外变更入口
/// （`beginEntry`/`appendOutput`/`finish`/`markInterrupted`）在 `MainActor` 上更新
/// `@Observable` 的 `state`，SwiftUI 观察安全；持久化在后台异步执行。
///
/// 关键不变量——**记录层是旁路**（Req 5.4 / Property 8）：所有变更入口均为 `Void`
/// 且不 `throw`，记录/持久化过程中的任何失败都被 service 内部吞掉并转为诊断日志，
/// 从而保证底层 git 编排的返回/抛出与「未记录」时完全一致。
///
/// service 以内存中的 `entries` 字典为权威源（source of truth），每次变更后镜像到
/// `state`（通过 `upsert`/`apply`）并触发后台 `persist()` 落盘。
@MainActor
final class OperationHistoryService {
    /// entry 归属的 `Repo_Context` 标识（通常为 repoPath）。
    let repoContextID: String

    /// 供 UI 观察的只读投影。
    let state: OperationHistoryState

    /// 可注入的持久化后端，便于测试与失败注入。
    private let store: OperationHistoryStoring

    /// 可注入时钟，便于时间戳断言。
    private let clock: () -> Date

    /// 内存权威历史，保留插入顺序，按 `id` 定位便于原位更新。
    private var entries: [OperationLogEntry] = []
    private var indexByID: [UUID: Int] = [:]

    // MARK: Init

    init(
        repoContextID: String,
        store: OperationHistoryStoring,
        clock: @escaping () -> Date = Date.init
    ) {
        self.repoContextID = repoContextID
        self.store = store
        self.clock = clock
        self.state = OperationHistoryState()
    }

    // MARK: Loading

    /// 打开仓库时加载已持久化历史（2.2）。
    ///
    /// 缺失文件时以空历史初始化（2.4）；损坏/无法解析时同样以空历史继续运行并记录
    /// 一条可诊断的错误信息（2.5），绝不崩溃。加载在后台线程读盘后跳回主线程投影。
    func loadFromDisk() async {
        let store = self.store
        let loaded: [OperationLogEntry]
        do {
            loaded = try await Task.detached(priority: .utility) {
                try store.load()
            }.value
        } catch {
            // 损坏/无法解析（或其他读取失败）→ 以空历史继续并记诊断日志（2.5）。
            Self.diagnostic("load failed for \(repoContextID): \(error)")
            loaded = []
        }

        entries = loaded
        rebuildIndex()
        state.apply(loaded)
    }

    // MARK: Classification

    /// 分类：是否为会修改仓库状态的 `Mutating_Operation`。
    ///
    /// 当前 `GitOperationKind` 仅枚举了变更类（streaming + 本地变更）操作，因此全部为
    /// mutating；`Read_Only_Operation`（log/status/diff 等）不进入该枚举，也不会被记录（1.3）。
    static func isMutating(_ kind: GitOperationKind) -> Bool {
        switch kind {
        case .fetch, .fetchPrune, .pull, .pullFF, .pullRebase, .pullForce,
             .push, .pushForce, .pushTag,
             .commit, .merge, .rebase, .checkout, .reset, .stash:
            return true
        }
    }

    // MARK: Mutation entry points（均为 Void 且不 throw —— 旁路不变量 5.4）

    /// 开始一条记录并返回其 `id`（1.1）。
    ///
    /// 仅对 `Mutating_Operation` 记录（1.3）。创建一条 `result == .running` 的 entry，
    /// 记录类型、完整命令、开始时间戳与归属 `Repo_Context`，随后镜像到 `state` 并落盘。
    @discardableResult
    func beginEntry(kind: GitOperationKind, command: [String]) -> UUID {
        let id = UUID()
        guard Self.isMutating(kind) else {
            // 非变更类不记录（1.3）；仍返回一个 id 以简化调用点，但不加入历史。
            return id
        }

        let entry = OperationLogEntry(
            id: id,
            kind: kind,
            command: command,
            startedAt: clock(),
            repoContextID: repoContextID
        )

        entries.append(entry)
        indexByID[id] = entries.count - 1
        state.upsert(entry)
        persist()
        return id
    }

    /// 流式增量追加输出（3.1/3.2）。触发 `state.version` 递增以驱动 UI 实时刷新（3.3）。
    ///
    /// 未知 `id`（如非记录操作返回的 id）安全忽略，保持旁路语义。
    func appendOutput(_ id: UUID, stdout: Data?, stderr: Data?) {
        guard let index = indexByID[id] else { return }
        entries[index].appendOutput(stdout: stdout, stderr: stderr)
        state.upsert(entries[index])
        persist()
    }

    /// 完成一条记录（1.2/3.4）：记录完成时间戳、退出码，并按退出码派生成功/失败结果。
    ///
    /// 本地变更类在此一次性传入捕获输出（1.5）；streaming 类可传 `captured` 覆盖为
    /// 聚合结果（与增量累积等价），也可传 `nil` 保留已增量收集的输出。
    func finish(_ id: UUID, exitCode: Int32, captured: OperationOutput?) {
        guard let index = indexByID[id] else { return }
        entries[index].finish(at: clock(), exitCode: exitCode, captured: captured)
        state.upsert(entries[index])
        persist()
    }

    /// 标记为中断态（5.2）：保留已收集输出，记录中断时刻。
    func markInterrupted(_ id: UUID) {
        guard let index = indexByID[id] else { return }
        entries[index].markInterrupted(at: clock())
        state.upsert(entries[index])
        persist()
    }

    // MARK: Persistence

    /// 每次变更后异步持久化（2.1）。
    ///
    /// 在后台任务中写盘以避免阻塞主线程；写入失败仅记诊断日志并保留内存历史（5.1/5.4），
    /// 绝不向 git 编排传播。对内存 `entries` 做值拷贝快照后交给后台线程，避免数据竞争。
    private func persist() {
        let snapshot = entries
        let store = self.store
        let contextID = repoContextID
        Task.detached(priority: .utility) {
            do {
                try store.save(snapshot)
            } catch {
                Self.diagnostic("persist failed for \(contextID): \(error)")
            }
        }
    }

    // MARK: Helpers

    /// 重建 `id → index` 映射（加载后或整表替换时）。
    private func rebuildIndex() {
        indexByID.removeAll(keepingCapacity: true)
        for (index, entry) in entries.enumerated() {
            indexByID[entry.id] = index
        }
    }

    /// 可诊断的错误日志（沿用仓库既有 `print("[Prefix] ...")` 诊断风格）。
    ///
    /// `nonisolated` 以便在后台持久化任务（脱离 MainActor）中调用（5.1）。
    private nonisolated static func diagnostic(_ message: @autoclosure () -> String) {
        print("[OperationHistory] \(message())")
    }
}
