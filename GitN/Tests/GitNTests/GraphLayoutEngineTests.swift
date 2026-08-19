import XCTest
@testable import GitN

final class GraphLayoutEngineTests: XCTestCase {

    private func commit(_ hash: String, parents: [String] = []) -> CommitInfo {
        CommitInfo(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            parentHashes: parents,
            authorName: "Tester",
            authorEmail: "tester@example.com",
            date: "2024-01-01",
            message: hash,
            refs: []
        )
    }

    /// Reproduces the reported bug: an independently-created root commit
    /// (e.g. an initial "Update README" commit on its own `develop` branch,
    /// with no parent) gets rendered while an *unrelated* lane is still
    /// actively passing through column 1 (that lane's own parent hasn't
    /// been reached yet in the walk). Root commits used to always default
    /// to column 1 (`if newPos < 1 { newPos = 1 }`), which placed the
    /// orphan commit's dot directly on top of the unrelated lane's
    /// passthrough line — making it look visually connected even though no
    /// `GraphLine` actually links them.
    ///
    /// History shape (child -> parent), in the order CommitWalker emits
    /// rows (newest first):
    ///   sideTip     -> sideParent   (sideParent appears several rows later)
    ///   orphanRoot  -> (no parents, unrelated to the side branch)
    ///   ...
    ///   sideParent  -> (no parents)
    func testDisconnectedRootCommitDoesNotOverlapUnrelatedOpenLane() {
        let commits = [
            commit("sideTip", parents: ["sideParent"]),
            commit("orphanRoot", parents: []),
            commit("sideParent", parents: [])
        ]

        let entries = GraphLayoutEngine.computeEntries(for: commits)

        let orphanEntry = try! XCTUnwrap(entries["orphanRoot"])

        // The side branch's lane is still open (waiting for sideParent) and
        // occupies column 1 as a passthrough at this row.
        let sideLanePassthroughColumn = 1

        // The orphan root must not be drawn in the same column as the
        // still-open, unrelated lane — otherwise its dot sits on top of
        // that lane's connecting line and looks like part of the same chain.
        XCTAssertNotEqual(
            orphanEntry.position, sideLanePassthroughColumn,
            "An unrelated root commit must not share a column with a still-open, unrelated lane"
        )
    }

    func testLinearHistoryStaysInSingleColumn() {
        let commits = [
            commit("c3", parents: ["c2"]),
            commit("c2", parents: ["c1"]),
            commit("c1", parents: [])
        ]

        let entries = GraphLayoutEngine.computeEntries(for: commits)

        for hash in ["c3", "c2", "c1"] {
            XCTAssertEqual(entries[hash]?.position, 1)
        }
    }

    func testMergeCommitCreatesLineToSecondParentLane() {
        let commits = [
            commit("merge", parents: ["mainParent", "sideParent"]),
            commit("mainParent", parents: []),
            commit("sideParent", parents: [])
        ]

        let entries = GraphLayoutEngine.computeEntries(for: commits)

        let mergeEntry = try! XCTUnwrap(entries["merge"])
        XCTAssertEqual(mergeEntry.position, 1)
        // A merge commit draws an extra line down to the newly-created lane
        // for its second parent, distinct from its own column.
        XCTAssertTrue(mergeEntry.lines.contains { $0.to != $0.from || $0.from != mergeEntry.position })
        XCTAssertEqual(mergeEntry.lines.count, 2)
    }
}
