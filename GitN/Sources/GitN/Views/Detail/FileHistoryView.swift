import SwiftUI

struct FileHistoryPanelContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let viewModel: RepoViewModel
    let showsToolbar: Bool

    @State private var commandBridge = MonacoCommandBridge()

    private var filePath: String { viewModel.fileHistoryPath }
    private var commits: [CommitInfo] { viewModel.fileHistoryCommits }
    private var selectedCommit: CommitInfo? { viewModel.fileHistorySelectedCommit }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if showsToolbar {
                    toolbar
                    Divider()
                }

                let commitListHeight = min(max(geo.size.height * 0.42, 220), 360)

                commitList
                    .frame(height: commitListHeight)

                Divider()

                diffView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(filePath)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text("(\(commits.count) commits)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Close") {
                viewModel.closeFileHistory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var commitList: some View {
        Group {
            if viewModel.isLoadingFileHistory {
                VStack {
                    ProgressView("Loading history...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                Text("No history found for this file")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(commits) { commit in
                            fileHistoryRow(commit)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await viewModel.selectFileHistoryCommit(commit) }
                                }
                        }
                    }
                }
            }
        }
    }

    private func fileHistoryRow(_ commit: CommitInfo) -> some View {
        let isSelected = selectedCommit?.hash == commit.hash
        return HStack(spacing: 0) {
            Text(commit.shortHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(briefDate(commit.date))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(commit.authorName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            Text(commit.message)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
    }

    private var diffView: some View {
        Group {
            if let diff = viewModel.fileHistoryParsedDiff, hasDisplayableTextContent {
                MonacoInspectorView(
                    mode: .diff,
                    isDark: colorScheme == .dark,
                    preview: nil,
                    items: [
                        MonacoDiffPayload(
                            path: diff.newPath ?? filePath,
                            language: RepoViewModel.monacoLanguage(for: filePath.sourceLanguage),
                            originalText: viewModel.fileHistoryBaseText,
                            modifiedText: viewModel.fileHistoryCurrentText,
                            isEditable: false,
                            primaryHunkAction: nil,
                            showsDiscardAction: false,
                            hunkControls: [],
                            lineBlames: []
                        )
                    ],
                    commandBridge: commandBridge,
                    onContentChange: { _, _ in },
                    onHunkAction: nil,
                    onSaveRequest: nil,
                    sourceIdentity: "\(viewModel.repoPath)|history|\(selectedCommit?.hash ?? "")"
                )
            } else if selectedCommit != nil && !viewModel.fileHistoryDiff.isEmpty {
                Text("This history entry has no textual hunks to display")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedCommit != nil {
                VStack {
                    ProgressView("Loading diff...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a commit to view changes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var hasDisplayableTextContent: Bool {
        !viewModel.fileHistoryBaseText.isEmpty || !viewModel.fileHistoryCurrentText.isEmpty
    }

    private func briefDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: " ")
        guard parts.count >= 1 else { return dateStr }
        return String(parts[0])
    }
}
