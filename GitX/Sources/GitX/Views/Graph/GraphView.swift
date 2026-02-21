import SwiftUI

struct GraphView: View {
    let viewModel: RepoViewModel

    private let rowHeight: CGFloat = 30
    private let columnWidth: CGFloat = 8
    private let leftMargin: CGFloat = 4
    private let graphAreaWidth: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            graphHeader
            Divider()

            if viewModel.commits.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                scrollContent
            }
        }
        .background(Color(.textBackgroundColor))
    }

    private var graphHeader: some View {
        HStack(spacing: 0) {
            Text("Graph")
                .frame(width: graphAreaWidth, alignment: .leading)
            Divider().frame(height: 16)
            Text("Description")
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 16)
            Text("Date")
                .frame(width: 140, alignment: .leading)
            Divider().frame(height: 16)
            Text("Author")
                .frame(width: 130, alignment: .leading)
            Divider().frame(height: 16)
            Text("SHA")
                .frame(width: 70, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No commits yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                    GraphRowView(
                        commit: commit,
                        graphEntry: viewModel.graphEntries[commit.hash],
                        isSelected: viewModel.selectedCommit?.hash == commit.hash,
                        rowHeight: rowHeight,
                        columnWidth: columnWidth,
                        leftMargin: leftMargin,
                        graphAreaWidth: graphAreaWidth,
                        currentBranch: viewModel.currentBranch
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.selectCommit(commit) }
                    }

                    if index < viewModel.commits.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }
}

// MARK: - Row

struct GraphRowView: View {
    let commit: CommitInfo
    let graphEntry: CommitGraphEntry?
    let isSelected: Bool
    let rowHeight: CGFloat
    let columnWidth: CGFloat
    let leftMargin: CGFloat
    let graphAreaWidth: CGFloat
    let currentBranch: String

    var body: some View {
        HStack(spacing: 0) {
            graphCanvas
                .frame(width: graphAreaWidth, height: rowHeight)

            descriptionCell
                .frame(maxWidth: .infinity, alignment: .leading)

            if commit.isUncommitted {
                Text("")
                    .frame(width: 140, alignment: .leading)
                Text("")
                    .frame(width: 130, alignment: .leading)
                Text("")
                    .frame(width: 70, alignment: .leading)
            } else {
                Text(formattedDate)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .leading)
                    .lineLimit(1)

                Text(commit.authorName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                    .lineLimit(1)

                Text(commit.shortHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 70, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color(.selectedContentBackgroundColor).opacity(0.2)
            } else if commit.isUncommitted {
                Color.orange.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }

    private func columnCenter(_ col: Int) -> CGFloat {
        leftMargin + columnWidth * CGFloat(col) + columnWidth / 2
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        Canvas { context, size in
            guard let entry = graphEntry else { return }
            let h = size.height
            let midY = h / 2
            let dotX = columnCenter(entry.dotColumn)
            let lineWidth: CGFloat = 2.0

            for line in entry.lines {
                guard let path = buildPath(for: line, dotColumn: entry.dotColumn, height: h)
                else { continue }

                let color = entry.isUncommitted
                    ? Color.gray.opacity(0.6)
                    : GraphColors.color(for: line.colorIndex)

                if line.parentIndex != line.childIndex {
                    context.stroke(path, with: .color(Color(.textBackgroundColor)),
                                   style: StrokeStyle(lineWidth: lineWidth + 1.0, lineCap: .round, lineJoin: .round))
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }

            let dotSize: CGFloat = 6.0
            let dotRect = CGRect(
                x: dotX - dotSize / 2,
                y: midY - dotSize / 2,
                width: dotSize, height: dotSize
            )
            let dotColor = GraphColors.color(for: entry.dotColorIndex)

            if commit.isUncommitted {
                let grayDot = Color.gray.opacity(0.6)
                context.fill(Path(ellipseIn: dotRect.insetBy(dx: -1, dy: -1)),
                             with: .color(Color(.textBackgroundColor)))
                context.stroke(Path(ellipseIn: dotRect),
                               with: .color(grayDot), lineWidth: 1.5)
            } else {
                context.fill(Path(ellipseIn: dotRect.insetBy(dx: -1, dy: -1)),
                             with: .color(Color(.textBackgroundColor)))
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
                context.stroke(Path(ellipseIn: dotRect),
                               with: .color(dotColor.opacity(0.7)), lineWidth: 1)
            }
        }
    }

    /// Builds a Bezier-curved path for a single HistoryLine.
    ///
    /// Y=0 is TOP (child / newer commit), Y=height is BOTTOM (parent / older commit).
    /// The dot sits at (dotColumn, midY).
    ///
    /// Every branch line is guaranteed to start from a dot and end at a dot:
    ///  - `childIndex == nil`  → the line **originates** at this row's dot
    ///  - `parentIndex == nil` → the line **terminates** at this row's dot
    ///  - both non-nil         → pass-through (connects dots in other rows)
    private func buildPath(for line: HistoryLine, dotColumn: Int, height: CGFloat) -> Path? {
        let midY = height / 2

        switch (line.parentIndex, line.childIndex) {

        // Incoming line: enters from top at childIdx column → converges to this row's dot
        case (nil, let childIdx?):
            var path = Path()
            let topX = columnCenter(childIdx)
            let dotX = columnCenter(dotColumn)
            path.move(to: CGPoint(x: topX, y: 0))
            if childIdx == dotColumn {
                path.addLine(to: CGPoint(x: dotX, y: midY))
            } else {
                path.addCurve(
                    to: CGPoint(x: dotX, y: midY),
                    control1: CGPoint(x: topX, y: midY * 0.6),
                    control2: CGPoint(x: dotX, y: midY * 0.4)
                )
            }
            return path

        // Outgoing line: leaves from this row's dot → exits at bottom at parentIdx column
        case (let parentIdx?, nil):
            var path = Path()
            let dotX = columnCenter(dotColumn)
            let bottomX = columnCenter(parentIdx)
            path.move(to: CGPoint(x: dotX, y: midY))
            if parentIdx == dotColumn {
                path.addLine(to: CGPoint(x: bottomX, y: height))
            } else {
                path.addCurve(
                    to: CGPoint(x: bottomX, y: height),
                    control1: CGPoint(x: dotX, y: midY + midY * 0.6),
                    control2: CGPoint(x: bottomX, y: midY + midY * 0.4)
                )
            }
            return path

        // Pass-through: enters top at childIdx, exits bottom at parentIdx (connects dots in other rows)
        case (let parentIdx?, let childIdx?):
            var path = Path()
            let topX = columnCenter(childIdx)
            let bottomX = columnCenter(parentIdx)
            path.move(to: CGPoint(x: topX, y: 0))
            if childIdx == parentIdx {
                path.addLine(to: CGPoint(x: bottomX, y: height))
            } else {
                path.addCurve(
                    to: CGPoint(x: bottomX, y: height),
                    control1: CGPoint(x: topX, y: height * 0.5),
                    control2: CGPoint(x: bottomX, y: height * 0.5)
                )
            }
            return path

        case (nil, nil):
            return nil
        }
    }

    // MARK: - Description Cell

    private var descriptionCell: some View {
        HStack(spacing: 4) {
            if commit.isUncommitted {
                Text("Uncommitted Changes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Text(commit.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(commit.refs, id: \.self) { ref in
                    RefBadge(refName: ref, currentBranch: currentBranch)
                }
                Text(commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }

    private var formattedDate: String {
        RelativeDateFormatter.format(commit.date)
    }
}

// MARK: - Ref Badge

struct RefBadge: View {
    let refName: String
    let currentBranch: String

    var body: some View {
        Text(cleanName)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.2))
                    .overlay(Capsule().strokeBorder(badgeColor.opacity(0.5), lineWidth: 0.5))
            )
            .foregroundStyle(badgeColor)
    }

    private var cleanName: String {
        refName
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "origin/", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var badgeColor: Color {
        if refName.contains("HEAD") {
            return .green
        } else if refName.contains("tag:") {
            return .yellow
        } else if refName.contains("origin/") || refName.contains("remote") {
            return .blue
        } else {
            return .orange
        }
    }
}

// MARK: - Relative Date Formatting

private enum RelativeDateFormatter {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func format(_ raw: String) -> String {
        guard let date = parser.date(from: raw) else {
            let parts = raw.split(separator: " ")
            guard parts.count >= 2 else { return raw }
            return "\(parts[0]) \(parts[1])"
        }

        let calendar = Calendar.current
        let now = Date()
        let time = timeOnly.string(from: date)

        if calendar.isDateInToday(date) {
            return "今天 \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(time)"
        }
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
        if date >= twoDaysAgo && date < calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!) {
            return "前天 \(time)"
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDay.string(from: date)
        }
        return full.string(from: date)
    }
}

// MARK: - Colors (matching Xit's lineColors)

enum GraphColors {
    static let colors: [Color] = [
        .blue, .green, .red, .brown, .cyan,
        .gray, .pink, .purple, .orange, .indigo,
        .yellow, .mint, .teal,
    ]

    static func color(for index: Int) -> Color {
        colors[abs(index) % colors.count]
    }
}
