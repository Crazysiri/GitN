import SwiftUI

struct FileHistoryView: View {
    let viewModel: RepoViewModel

    private var filePath: String { viewModel.fileHistoryPath }
    private var commits: [CommitInfo] { viewModel.fileHistoryCommits }
    private var selectedCommit: CommitInfo? { viewModel.fileHistorySelectedCommit }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VSplitView {
                commitList
                    .frame(minHeight: 200)
                diffView
                    .frame(minHeight: 150)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Toolbar

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

    // MARK: - Commit List

    private var commitList: some View {
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

    private func fileHistoryRow(_ commit: CommitInfo) -> some View {
        let isSelected = selectedCommit?.hash == commit.hash
        return HStack(spacing: 0) {
            // Commit hash
            Text(commit.shortHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Date
            Text(briefDate(commit.date))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            // Author
            Text(commit.authorName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            // Message
            Text(commit.message)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
    }

    // MARK: - Diff View

    private var diffView: some View {
        Group {
            if let diff = viewModel.fileHistoryParsedDiff, !diff.hunks.isEmpty {
                fileHistoryDiffContent(diff)
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

    private func fileHistoryDiffContent(_ diff: ParsedDiff) -> some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                        hunkHeader(hunk)
                        hunkBody(hunk)
                    }
                }
                .frame(minWidth: geo.size.width, alignment: .topLeading)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func hunkHeader(_ hunk: ParsedHunk) -> some View {
        HStack(spacing: 6) {
            Text(hunk.rawHeader)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.separatorColor).opacity(0.15))
    }

    private func hunkBody(_ hunk: ParsedHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                HStack(spacing: 0) {
                    Text(line.oldLineNum.map(String.init) ?? "")
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(line.newLineNum.map(String.init) ?? "")
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Rectangle()
                        .fill(Color(.separatorColor).opacity(0.3))
                        .frame(width: 1)
                        .padding(.horizontal, 3)

                    Text(prefixChar(line.kind))
                        .frame(width: 12, alignment: .center)
                        .foregroundStyle(lineTextColor(line.kind))

                    Text(line.content)
                        .foregroundStyle(lineTextColor(line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.vertical, 0.5)
                .background(lineBackground(line.kind))
            }
        }
    }

    // MARK: - Helpers

    private func prefixChar(_ kind: HunkLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private func lineTextColor(_ kind: HunkLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .primary
        }
    }

    private func lineBackground(_ kind: HunkLine.Kind) -> Color {
        switch kind {
        case .addition: return .green.opacity(0.06)
        case .deletion: return .red.opacity(0.06)
        case .context: return .clear
        }
    }

    private func briefDate(_ dateStr: String) -> String {
        // Input format: 2026-01-28 12:34:56 +0800
        let parts = dateStr.split(separator: " ")
        guard parts.count >= 1 else { return dateStr }
        return String(parts[0])
    }
}
