import SwiftUI

/// A drawable line segment within a single row, ported from gitx's PBGitGraphLine.
///
/// Each line represents half a row's connection:
/// - `upper = true`: line from column `from` at the TOP edge to column `to` at the CENTER
/// - `upper = false`: line from column `from` at the BOTTOM edge to column `to` at the CENTER
///
/// Columns are 1-indexed to match gitx's convention.
struct GraphLine: Equatable, Sendable {
    let upper: Bool
    let from: Int
    let to: Int
    let colorIndex: Int
    var isUncommittedLink: Bool = false
}

/// Per-commit graph layout data, ported from gitx's PBGraphCellInfo.
struct CommitGraphEntry: Equatable, Sendable {
    /// 1-indexed column position for the commit dot
    let position: Int
    let dotColorIndex: Int
    let lines: [GraphLine]
    let numColumns: Int
    let isUncommitted: Bool
}

/// Stateful graph layout engine that processes commits one at a time,
/// ported from gitx's PBGitGrapher. Allows incremental/streaming graph
/// decoration: call `processCommit` repeatedly as new commits arrive.
final class IncrementalGraphLayoutEngine: @unchecked Sendable {

    private final class Lane {
        var parentHash: String
        let colorIndex: Int
        var fromUncommitted: Bool

        init(colorIndex: Int, parentHash: String, fromUncommitted: Bool = false) {
            self.colorIndex = colorIndex
            self.parentHash = parentHash
            self.fromUncommitted = fromUncommitted
        }
    }

    private var previousLanes: [Lane?] = []
    private var nextLaneIndex = 0

    func processCommit(_ commit: CommitInfo) -> CommitGraphEntry {
        let commitHash = commit.hash
        let parents = commit.parentHashes
        let nParents = parents.count

        var currentLanes: [Lane?] = []
        var lines: [GraphLine] = []
        var newPos = -1
        var currentLane: Lane?
        var didFirst = false
        var dotColorIndex = 0

        // Phase 1: iterate over previous lanes, pass through or merge
        var i = 0
        for lane in previousLanes {
            i += 1
            guard let lane else { continue }

            if lane.parentHash == commitHash {
                let isULink = lane.fromUncommitted
                if !didFirst {
                    didFirst = true
                    currentLanes.append(lane)
                    currentLane = lane
                    newPos = currentLanes.count
                    dotColorIndex = lane.colorIndex
                    lines.append(GraphLine(upper: true, from: i, to: newPos, colorIndex: lane.colorIndex, isUncommittedLink: isULink))
                    if nParents > 0 {
                        lines.append(GraphLine(upper: false, from: newPos, to: newPos, colorIndex: lane.colorIndex, isUncommittedLink: false))
                    }
                    lane.fromUncommitted = false
                } else {
                    lines.append(GraphLine(upper: true, from: i, to: newPos, colorIndex: lane.colorIndex, isUncommittedLink: isULink))
                }
            } else {
                let passULink = lane.fromUncommitted
                currentLanes.append(lane)
                let col = currentLanes.count
                lines.append(GraphLine(upper: true, from: i, to: col, colorIndex: lane.colorIndex, isUncommittedLink: passULink))
                lines.append(GraphLine(upper: false, from: col, to: col, colorIndex: lane.colorIndex, isUncommittedLink: passULink))
            }
        }

        // Phase 2: create lane for first parent if not already handled
        if !didFirst && nParents > 0 {
            let newLane = Lane(colorIndex: nextLaneIndex, parentHash: parents[0], fromUncommitted: commit.isUncommitted)
            nextLaneIndex += 1
            currentLanes.append(newLane)
            currentLane = newLane
            newPos = currentLanes.count
            dotColorIndex = newLane.colorIndex
            lines.append(GraphLine(upper: false, from: newPos, to: newPos, colorIndex: newLane.colorIndex))
        }

        // Phase 3: create lanes for additional parents (merge commits)
        var addedParent = false
        for parentIdx in 1..<max(1, nParents) {
            let parentHash = parents[parentIdx]
            var wasDisplayed = false

            var j = 0
            for existingLane in currentLanes {
                j += 1
                guard let existingLane else { continue }
                if existingLane.parentHash == parentHash {
                    lines.append(GraphLine(upper: false, from: j, to: newPos, colorIndex: existingLane.colorIndex))
                    wasDisplayed = true
                    break
                }
            }

            if !wasDisplayed {
                addedParent = true
                let newLane = Lane(colorIndex: nextLaneIndex, parentHash: parentHash)
                nextLaneIndex += 1
                currentLanes.append(newLane)
                lines.append(GraphLine(
                    upper: false, from: currentLanes.count, to: newPos, colorIndex: newLane.colorIndex
                ))
            }
        }

        let numColumns = addedParent ? currentLanes.count - 1 : currentLanes.count

        // Update current lane to point to first parent, or nullify for root commits
        if let cl = currentLane {
            if nParents > 0 {
                cl.parentHash = parents[0]
            } else {
                if let idx = currentLanes.firstIndex(where: { $0 === cl }) {
                    currentLanes[idx] = nil
                }
            }
        }

        if newPos < 1 { newPos = 1 }

        let entry = CommitGraphEntry(
            position: newPos,
            dotColorIndex: dotColorIndex,
            lines: lines,
            numColumns: numColumns,
            isUncommitted: commit.isUncommitted
        )

        previousLanes = currentLanes
        return entry
    }
}

/// Convenience batch wrapper around IncrementalGraphLayoutEngine.
enum GraphLayoutEngine {
    static func computeEntries(for commits: [CommitInfo]) -> [String: CommitGraphEntry] {
        guard !commits.isEmpty else { return [:] }
        let engine = IncrementalGraphLayoutEngine()
        var result: [String: CommitGraphEntry] = [:]
        result.reserveCapacity(commits.count)
        for commit in commits {
            result[commit.hash] = engine.processCommit(commit)
        }
        return result
    }
}
