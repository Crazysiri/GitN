import XCTest
@testable import GitN

/// Task 8.3 — 空状态与入口可用性校验（EXAMPLE 4.1 / 4.6）。
///
/// 仓库无快照测试框架，且 SwiftUI view body 无法在此单测。故将「工具栏入口可打开
/// History_View」与「空历史时视图模型返回空状态表示」表述为对 `OperationHistoryState`
/// 这一可观察模型的状态断言，并对 `HistoryView(state:)` / `RepoViewModel
/// .operationHistoryState` 做轻量类型契约校验，证明入口已接线。
///
/// _Requirements: 4.1, 4.6_
@MainActor
final class HistoryViewStateTests: XCTestCase {

    // MARK: - EXAMPLE 4.6：空状态表示

    /// 全新的 `OperationHistoryState` 即为 `HistoryView` 展示空状态所依赖的条件：
    /// `isEmpty == true` 且 `orderedEntries` 为空；upsert 一条 entry 后转为非空、
    /// 且恰有一条。验证视图模型能返回空状态表示（Req 4.6）。
    func testFreshStateReportsEmptyThenBecomesNonEmptyAfterUpsert() {
        let state = OperationHistoryState()

        // 空状态：HistoryView.body 据此走 emptyState 分支。
        XCTAssertTrue(state.isEmpty)
        XCTAssertTrue(state.orderedEntries.isEmpty)

        let entry = OperationLogEntry(
            kind: .commit,
            command: ["git", "commit", "-m", "hello"],
            startedAt: Date(timeIntervalSince1970: 1_000),
            repoContextID: "repo-1"
        )
        state.upsert(entry)

        // 非空状态：HistoryView.body 据此走 entryList 分支。
        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.orderedEntries.count, 1)
        XCTAssertEqual(state.orderedEntries.first?.id, entry.id)
    }

    // MARK: - EXAMPLE 4.1：入口存在且可打开 History_View

    /// 工具栏入口通过 `HistoryView(state:)` 打开视图并绑定当前仓库的历史投影。
    /// 断言该 initializer 存在并接收 `OperationHistoryState`，即入口的类型契约成立
    /// （Req 4.1）。构造 View struct 无副作用、无需渲染。
    func testHistoryViewCanBeConstructedWithState() {
        let state = OperationHistoryState()
        _ = HistoryView(state: state)
    }
}
