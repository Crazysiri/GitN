import SwiftUI

/// A drawable line segment within a single row.
/// Faithfully ported from Xit's HistoryLine.
///
/// - `childIndex`: column at the TOP of the row (where the line enters from above).
///   `nil` means the line originates at the commit dot.
/// - `parentIndex`: column at the BOTTOM of the row (where the line exits downward).
///   `nil` means the line terminates at the commit dot.
struct HistoryLine: Equatable, Sendable {
    let childIndex: Int?
    let parentIndex: Int?
    let colorIndex: Int
}

/// Per-commit graph layout data.
struct CommitGraphEntry: Equatable {
    let dotColumn: Int
    let dotColorIndex: Int
    let lines: [HistoryLine]
    /// True for the uncommitted-changes pseudo-row
    let isUncommitted: Bool
}

/// Exact port of Xit's CommitHistory.generateConnections + generateLines.
///
/// The algorithm maintains an ordered array of "active connections" (pipes)
/// flowing downward through the graph. Each connection targets a specific
/// parent commit hash. When a commit is encountered:
/// 1. The incoming pipe (targeting this commit) is found
/// 2. A new pipe to the first parent replaces/extends it
/// 3. Additional parent pipes are appended (for merge commits)
/// 4. A snapshot of all connections is taken
/// 5. Connections targeting this commit are removed
///
/// Then for each row, the snapshot is converted into HistoryLine segments.
enum GraphLayoutEngine {

    private struct Connection: Equatable {
        let parentHash: String
        let childHash: String
        let colorIndex: Int
    }

    static func computeEntries(for commits: [CommitInfo]) -> [String: CommitGraphEntry] {
        guard !commits.isEmpty else { return [:] }

        let snapshots = generateConnections(for: commits)
        var result: [String: CommitGraphEntry] = [:]
        result.reserveCapacity(commits.count)

        for (i, commit) in commits.enumerated() {
            let entry = generateLines(
                commitHash: commit.hash,
                connections: snapshots[i],
                isUncommitted: commit.isUncommitted
            )
            result[commit.hash] = entry
        }

        return result
    }

    // MARK: - Phase 1: generateConnections (Xit's CommitHistory.generateConnections)

    private static func generateConnections(for commits: [CommitInfo]) -> [[Connection]] {
        var snapshots: [[Connection]] = []
        snapshots.reserveCapacity(commits.count)
        var connections: [Connection] = []
        var nextColorIndex = 0

        for commit in commits {
            let commitHash = commit.hash

            let incomingIndex = connections.firstIndex { $0.parentHash == commitHash }
            let incomingColor = incomingIndex.map { connections[$0].colorIndex }

            if let firstParentHash = commit.parentHashes.first {
                let color: Int
                if let ic = incomingColor {
                    color = ic
                } else {
                    color = nextColorIndex
                    nextColorIndex += 1
                }

                let newConn = Connection(
                    parentHash: firstParentHash,
                    childHash: commitHash,
                    colorIndex: color
                )
                let insertIndex = incomingIndex.map { $0 + 1 } ?? connections.endIndex
                connections.insert(newConn, at: insertIndex)
            }

            for parentHash in commit.parentHashes.dropFirst() {
                connections.append(Connection(
                    parentHash: parentHash,
                    childHash: commitHash,
                    colorIndex: nextColorIndex
                ))
                nextColorIndex += 1
            }

            snapshots.append(connections)

            connections = connections.filter { $0.parentHash != commitHash }
        }

        return snapshots
    }

    // MARK: - Phase 2: generateLines (Xit's CommitHistory.generateLines)

    private static func generateLines(
        commitHash: String,
        connections: [Connection],
        isUncommitted: Bool = false
    ) -> CommitGraphEntry {
        var nextChildIndex = 0

        let parentOutlets: [String] = {
            var seen: [String] = []
            for conn in connections where conn.parentHash != commitHash {
                if !seen.contains(conn.parentHash) {
                    seen.append(conn.parentHash)
                }
            }
            return seen
        }()

        var parentLines: [String: (childIndex: Int, colorIndex: Int)] = [:]
        var generatedLines: [HistoryLine] = []
        var dotColumn: Int?
        var dotColorIndex: Int?

        for conn in connections {
            let commitIsParent = conn.parentHash == commitHash
            let commitIsChild = conn.childHash == commitHash

            let parentIndex: Int? = commitIsParent
                ? nil
                : parentOutlets.firstIndex(of: conn.parentHash)

            var childIndex: Int? = commitIsChild ? nil : nextChildIndex
            var colorIndex = conn.colorIndex

            if dotColumn == nil && (commitIsParent || commitIsChild) {
                dotColumn = nextChildIndex
                dotColorIndex = colorIndex
            }

            if let existing = parentLines[conn.parentHash] {
                if !commitIsChild {
                    childIndex = existing.childIndex
                    colorIndex = existing.colorIndex
                } else if !commitIsParent {
                    nextChildIndex += 1
                }
            } else {
                if !commitIsChild {
                    parentLines[conn.parentHash] = (
                        childIndex: nextChildIndex,
                        colorIndex: colorIndex
                    )
                }
                if !commitIsParent {
                    nextChildIndex += 1
                }
            }

            generatedLines.append(HistoryLine(
                childIndex: childIndex,
                parentIndex: parentIndex,
                colorIndex: colorIndex
            ))
        }

        return CommitGraphEntry(
            dotColumn: dotColumn ?? 0,
            dotColorIndex: dotColorIndex ?? 0,
            lines: generatedLines,
            isUncommitted: isUncommitted
        )
    }
}
