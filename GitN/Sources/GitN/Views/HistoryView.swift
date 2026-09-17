import SwiftUI

/// 工具栏「历史」浮层界面（4.2 / 4.3 / 4.4 / 4.6 / 3.3）。
///
/// 直接绑定一个 `OperationHistoryState`（`@Observable` 只读投影），展示当前
/// `Repo_Context` 的操作历史。列表按 `orderedEntries`（最近在前）展示类型、
/// 开始时间与结果；点击行展开显示命令、退出码与完整 stdout/stderr。
///
/// 视图保持 thin：所有展示派生逻辑（排序、行/详情视图模型、格式化）都由
/// `OperationHistoryState` 提供，本视图仅负责布局与交互。
///
/// 通过在 `body` 中读取 `state.version` 感知流式增量刷新——进行中的 streaming
/// entry 每次 `appendOutput` 都会递增 `version`，从而驱动 SwiftUI 实时重绘。
struct HistoryView: View {
    /// 当前 `Repo_Context` 的历史投影。由工具栏入口 / `RepoViewModel` 接线传入。
    let state: OperationHistoryState

    /// 当前展开查看详情的 entry id（单选展开）。
    @State private var expandedEntryID: OperationLogEntry.ID?

    var body: some View {
        // 读取 `version` 使 SwiftUI 观察流式增量刷新（3.3）。
        let _ = state.version

        VStack(spacing: 0) {
            header

            Divider()

            if state.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("操作历史")
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Empty state (4.6)

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("暂无操作历史")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("对该仓库执行的变更类 Git 操作会显示在这里。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Entry list (4.2 / 4.3)

    private var entryList: some View {
        List(state.orderedEntries) { entry in
            entryRow(entry)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func entryRow(_ entry: OperationLogEntry) -> some View {
        let row = state.rowViewModel(for: entry)
        let isExpanded = expandedEntryID == entry.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleExpansion(entry.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    resultBadge(result: entry.result, display: row.resultDisplay)

                    Text(row.kindDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    Text(row.startedAtDisplay)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                detail(for: entry)
                    .padding(.top, 8)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }

    /// 结果状态徽标（成功/失败/进行中/中断），使用系统语义色，随外观自适应。
    /// `display` 由 `HistoryRowViewModel.resultDisplay` 提供，保持展示文本单一来源。
    private func resultBadge(result: OperationResult, display: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: result))
                .frame(width: 7, height: 7)
            Text(display)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
    }

    private func color(for result: OperationResult) -> Color {
        switch result {
        case .running: return .accentColor
        case .success: return .green
        case .failure: return .red
        case .interrupted: return .orange
        }
    }

    // MARK: - Detail (4.4)

    @ViewBuilder
    private func detail(for entry: OperationLogEntry) -> some View {
        let detail = state.detailViewModel(for: entry)

        VStack(alignment: .leading, spacing: 8) {
            detailField(label: "命令", value: detail.commandLine)
            detailField(label: "退出码", value: detail.exitCodeDisplay)

            if !detail.stdoutText.isEmpty {
                outputSection(title: "stdout", text: detail.stdoutText)
            }
            if !detail.stderrText.isEmpty {
                outputSection(title: "stderr", text: detail.stderrText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailField(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outputSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separatorColor).opacity(0.55), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Interaction

    private func toggleExpansion(_ id: OperationLogEntry.ID) {
        if expandedEntryID == id {
            expandedEntryID = nil
        } else {
            expandedEntryID = id
        }
    }
}
