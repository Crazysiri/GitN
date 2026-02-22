import SwiftUI
import AppKit

struct ConflictMergeView: View {
    let viewModel: RepoViewModel
    @State private var currentConflictIndex = 0
    @State private var syncedScrollOffset: CGPoint = .zero

    private var file: ConflictFile? { viewModel.conflictMergeFile }
    private var sides: ConflictSides? { viewModel.conflictSides }
    private var totalConflicts: Int { sides?.markers.count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VSplitView {
                HSplitView {
                    oursPanel
                    theirsPanel
                }
                .frame(minHeight: 200)

                outputPanel
                    .frame(minHeight: 150)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                Text(file?.path ?? "")
                    .font(.system(size: 12, weight: .semibold))
                if totalConflicts > 0 {
                    Text("(\(totalConflicts) conflict\(totalConflicts == 1 ? "" : "s"))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Conflict navigator
            if totalConflicts > 0 {
                HStack(spacing: 4) {
                    Text("conflict \(currentConflictIndex + 1) of \(totalConflicts)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button(action: { navigateConflict(-1) }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(currentConflictIndex <= 0)

                    Button(action: { navigateConflict(1) }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(currentConflictIndex >= totalConflicts - 1)
                }
            }

            Divider().frame(height: 16)

            Button(action: { Task { await viewModel.saveConflictResolution() } }) {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: { viewModel.closeConflictMerge() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Ours (Target Branch) Panel

    private var oursPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                label: "A",
                labelColor: .blue,
                title: sides?.oursLabel ?? "Ours"
            )
            Divider()
            SyncedCodeView(
                content: sides?.oursContent ?? "",
                conflictRegions: sides?.markers ?? [],
                side: .ours,
                highlightColor: .blue,
                onTakeLine: { regionIdx in viewModel.takeOurs(regionIdx) }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Theirs (Source Branch) Panel

    private var theirsPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                label: "B",
                labelColor: .orange,
                title: sides?.theirsLabel ?? "Theirs"
            )
            Divider()
            SyncedCodeView(
                content: sides?.theirsContent ?? "",
                conflictRegions: sides?.markers ?? [],
                side: .theirs,
                highlightColor: .orange,
                onTakeLine: { regionIdx in viewModel.takeTheirs(regionIdx) }
            )
        }
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Output Panel

    private var outputPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor).opacity(0.5))

            Divider()

            OutputCodeView(lines: viewModel.conflictOutputLines, conflictRegions: sides?.markers ?? [])
        }
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Helpers

    private func panelHeader(label: String, labelColor: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(labelColor))

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func navigateConflict(_ delta: Int) {
        let newIdx = currentConflictIndex + delta
        guard newIdx >= 0, newIdx < totalConflicts else { return }
        currentConflictIndex = newIdx
    }
}

// MARK: - Side Indicator

enum ConflictSide {
    case ours, theirs
}

// MARK: - Synced Code View (for ours/theirs panes)

struct SyncedCodeView: View {
    let content: String
    let conflictRegions: [ConflictRegion]
    let side: ConflictSide
    let highlightColor: Color
    let onTakeLine: (Int) -> Void

    private var lines: [String] { content.components(separatedBy: "\n") }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    let regionIdx = conflictRegionIndex(for: idx)
                    let isConflict = regionIdx != nil

                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .frame(width: 36, alignment: .trailing)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.trailing, 4)

                        Rectangle()
                            .fill(Color(.separatorColor).opacity(0.3))
                            .frame(width: 1)

                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.leading, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isConflict, let ri = regionIdx {
                            Button(action: { onTakeLine(ri) }) {
                                Text("Take this line")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(highlightColor.opacity(0.15))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .strokeBorder(highlightColor.opacity(0.4), lineWidth: 0.5)
                                            )
                                    )
                                    .foregroundStyle(highlightColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                        }
                    }
                    .padding(.vertical, 0.5)
                    .background(isConflict ? highlightColor.opacity(0.08) : Color.clear)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func conflictRegionIndex(for lineIdx: Int) -> Int? {
        for (i, region) in conflictRegions.enumerated() {
            let range = side == .ours ? region.oursRange : region.theirsRange
            if range.contains(lineIdx) { return i }
        }
        return nil
    }
}

// MARK: - Output Code View

struct OutputCodeView: View {
    let lines: [String]
    let conflictRegions: [ConflictRegion]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .frame(width: 36, alignment: .trailing)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.trailing, 4)

                        Rectangle()
                            .fill(Color(.separatorColor).opacity(0.3))
                            .frame(width: 1)

                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.leading, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 0.5)
                }
            }
            .padding(.bottom, 8)
        }
    }
}
