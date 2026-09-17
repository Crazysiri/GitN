import Foundation
import Observation

// MARK: - HistoryRowViewModel

/// 列表行的展示投影（4.2 / 4.3）。纯值类型，由 `OperationHistoryState.rowViewModel(for:)`
/// 从一条 `OperationLogEntry` 派生，仅供 UI 直接绑定，无 I/O、无副作用。
struct HistoryRowViewModel: Equatable {
    /// 操作类型的展示文本。
    let kindDisplay: String
    /// 开始时间的展示文本。
    let startedAtDisplay: String
    /// 成功/失败/进行中/中断结果的展示文本。
    let resultDisplay: String
}

// MARK: - HistoryDetailViewModel

/// 展开详情的展示投影（4.4）。纯值类型，由 `OperationHistoryState.detailViewModel(for:)`
/// 从一条 `OperationLogEntry` 派生。
struct HistoryDetailViewModel: Equatable {
    /// 完整 git 命令行（含 "git" 前缀与全部参数）。
    let commandLine: String
    /// 退出状态码的展示文本（进行中/中断且无退出码时给出占位）。
    let exitCodeDisplay: String
    /// 有损解码后的 stdout 文本。
    let stdoutText: String
    /// 有损解码后的 stderr 文本。
    let stderrText: String
}

// MARK: - OperationHistoryState

/// 单个 `Repo_Context` 的内存历史投影（`@Observable` 只读投影）。
///
/// 承担纯展示派生逻辑（排序、行/详情视图模型），不做 I/O。对齐 `RepoReflogState`
/// 的「纯派生」定位。所有变更由 `OperationHistoryService` 在主线程通过 `apply(_:)`
/// / `upsert(_:)` 触发，SwiftUI 通过观察 `entries` 与 `version` 实时刷新。
@Observable
final class OperationHistoryState {
    /// 全部操作历史 entry（未排序，保留插入/加载顺序）。
    private(set) var entries: [OperationLogEntry] = []

    /// 单调递增版本号，供 UI 感知流式增量刷新（3.3）。
    private(set) var version: Int = 0

    /// 按开始时间排序（最近在前），使最近操作可被稳定识别（4.3 / Property 10）。
    var orderedEntries: [OperationLogEntry] {
        entries.sorted { $0.startedAt > $1.startedAt }
    }

    /// 历史是否为空，用于空状态提示（4.6）。
    var isEmpty: Bool { entries.isEmpty }

    // MARK: 视图模型映射（纯函数、可单测）

    /// 从一条 entry 派生列表行视图模型（4.2 / 4.3 / Property 7）。
    func rowViewModel(for entry: OperationLogEntry) -> HistoryRowViewModel {
        HistoryRowViewModel(
            kindDisplay: Self.kindDisplay(entry.kind),
            startedAtDisplay: Self.dateDisplay(entry.startedAt),
            resultDisplay: Self.resultDisplay(entry.result)
        )
    }

    /// 从一条 entry 派生展开详情视图模型（4.4 / Property 7）。
    func detailViewModel(for entry: OperationLogEntry) -> HistoryDetailViewModel {
        HistoryDetailViewModel(
            commandLine: entry.command.joined(separator: " "),
            exitCodeDisplay: Self.exitCodeDisplay(entry.exitCode),
            stdoutText: entry.output.stdoutText,
            stderrText: entry.output.stderrText
        )
    }

    // MARK: 内部变更入口（由 service 在主线程调用）

    /// 用一批 entry 替换当前历史（如从磁盘加载后一次性投影）。递增 `version`。
    func apply(_ entries: [OperationLogEntry]) {
        self.entries = entries
        version &+= 1
    }

    /// 按 `id` 插入或更新一条 entry；已存在则原位替换，否则追加。递增 `version`（3.3）。
    func upsert(_ entry: OperationLogEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        version &+= 1
    }

    // MARK: - 展示格式化（纯静态、无本地化状态）

    private static func kindDisplay(_ kind: GitOperationKind) -> String {
        switch kind {
        case .fetch: return "Fetch"
        case .fetchPrune: return "Fetch (prune)"
        case .pull: return "Pull"
        case .pullFF: return "Pull (fast-forward)"
        case .pullRebase: return "Pull (rebase)"
        case .pullForce: return "Pull (force)"
        case .push: return "Push"
        case .pushForce: return "Push (force)"
        case .pushTag: return "Push tag"
        case .commit: return "Commit"
        case .merge: return "Merge"
        case .rebase: return "Rebase"
        case .checkout: return "Checkout"
        case .reset: return "Reset"
        case .stash: return "Stash"
        }
    }

    private static func resultDisplay(_ result: OperationResult) -> String {
        switch result {
        case .running: return "Running"
        case .success: return "Success"
        case .failure: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }

    private static func exitCodeDisplay(_ exitCode: Int32?) -> String {
        guard let exitCode else { return "—" }
        return String(exitCode)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    private static func dateDisplay(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
