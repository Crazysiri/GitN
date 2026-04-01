import XCTest
@testable import GitN

final class GitServiceConflictSidesTests: XCTestCase {
    func testBuildConflictSidesParsesZDdiff3AndProjectsBaseIntoOutput() {
        let baseLines = [
            "header",
            "base-title",
            "base-body",
            "shared-middle",
            "ours-duplicated-block",
            "base-tail",
            "footer",
        ]

        let sides = GitService.buildConflictSides(
            mergedText: [
                "header",
                "<<<<<<< Current",
                "ours-title-corrupted",
                "ours-extra",
                "||||||| Base",
                "base-title",
                "base-body",
                "=======",
                "theirs-title-short",
                ">>>>>>> Incoming",
                "shared-middle",
                "ours-duplicated-block",
                "<<<<<<< Current",
                "ours-tail",
                "||||||| Base",
                "base-tail",
                "=======",
                "theirs-tail",
                ">>>>>>> Incoming",
                "footer",
            ].joined(separator: "\n"),
            baseLines: baseLines,
            oursLines: [
                "header",
                "ours-title-corrupted",
                "ours-extra",
                "shared-middle",
                "ours-duplicated-block",
                "ours-tail",
                "footer",
            ],
            theirsLines: [
                "header",
                "theirs-title-short",
                "shared-middle",
                "ours-duplicated-block",
                "theirs-tail",
                "footer",
            ],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        XCTAssertEqual(
            sides.outputLines,
            [
                "header",
                "base-title",
                "base-body",
                "shared-middle",
                "ours-duplicated-block",
                "base-tail",
                "footer",
            ]
        )
        XCTAssertEqual(
            sides.markers,
            [
                ConflictRegion(
                    id: 0,
                    oursRange: 1..<3,
                    theirsRange: 1..<2,
                    baseRange: 1..<3,
                    outputRange: 1..<3,
                    currentLines: [
                        "ours-title-corrupted",
                        "ours-extra",
                    ],
                    baseLines: [
                        "base-title",
                        "base-body",
                    ],
                    incomingLines: [
                        "theirs-title-short",
                    ],
                    rawConflictLines: [
                        "<<<<<<< Current",
                        "ours-title-corrupted",
                        "ours-extra",
                        "||||||| Base",
                        "base-title",
                        "base-body",
                        "=======",
                        "theirs-title-short",
                        ">>>>>>> Incoming",
                    ]
                ),
                ConflictRegion(
                    id: 1,
                    oursRange: 5..<6,
                    theirsRange: 4..<5,
                    baseRange: 5..<6,
                    outputRange: 5..<6,
                    currentLines: [
                        "ours-tail",
                    ],
                    baseLines: [
                        "base-tail",
                    ],
                    incomingLines: [
                        "theirs-tail",
                    ],
                    rawConflictLines: [
                        "<<<<<<< Current",
                        "ours-tail",
                        "||||||| Base",
                        "base-tail",
                        "=======",
                        "theirs-tail",
                        ">>>>>>> Incoming",
                    ]
                ),
            ]
        )
    }

    func testBuildConflictSidesPreservesMergedLinesOutsideConflicts() {
        let sides = GitService.buildConflictSides(
            mergedText: [
                "prologue",
                "kept-from-worktree",
                "<<<<<<< Current",
                "ours",
                "||||||| Base",
                "base-choice",
                "=======",
                "theirs",
                ">>>>>>> Incoming",
                "another-worktree-line",
                "epilogue",
            ].joined(separator: "\n"),
            baseLines: [
                "prologue",
                "kept-from-base",
                "base-choice",
                "another-worktree-line",
                "epilogue",
            ],
            oursLines: [
                "prologue",
                "kept-from-worktree",
                "ours",
                "another-worktree-line",
                "epilogue",
            ],
            theirsLines: [
                "prologue",
                "kept-from-worktree",
                "theirs",
                "another-worktree-line",
                "epilogue",
            ],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        XCTAssertEqual(
            sides.outputLines,
            [
                "prologue",
                "kept-from-worktree",
                "base-choice",
                "another-worktree-line",
                "epilogue",
            ]
        )
        XCTAssertEqual(sides.markers.first?.outputRange, 2..<3)
    }

    func testBuildConflictSidesHandlesEmptyIncomingSide() {
        let sides = GitService.buildConflictSides(
            mergedText: [
                "before",
                "<<<<<<< Current",
                "ours-only",
                "||||||| Base",
                "base-only",
                "=======",
                ">>>>>>> Incoming",
                "after",
            ].joined(separator: "\n"),
            baseLines: ["before", "base-only", "after"],
            oursLines: ["before", "ours-only", "after"],
            theirsLines: ["before", "after"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        XCTAssertEqual(sides.theirsLines, ["before", "after"])
        XCTAssertEqual(sides.markers.first?.theirsRange, 1..<1)
    }

    func testBuildConflictSidesAnchorsEmptyIncomingBeforeNearestAfterContextWhenCursorDrifts() {
        let sides = GitService.buildConflictSides(
            mergedText: [
                "header",
                "podfile_path = project_root / \"Podfile\"",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "<<<<<<< Current",
                "ours-only",
                "||||||| Base",
                "base-only",
                "=======",
                ">>>>>>> Incoming",
                "if not github_ok and not tuna_ok:",
                "    logger.warning(\"skip\")",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "    result = subprocess.run()",
            ].joined(separator: "\n"),
            baseLines: [
                "header",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "base-only",
                "if not github_ok and not tuna_ok:",
                "    logger.warning(\"skip\")",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "    result = subprocess.run()",
            ],
            oursLines: [
                "header",
                "podfile_path = project_root / \"Podfile\"",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "ours-only",
                "if not github_ok and not tuna_ok:",
                "    logger.warning(\"skip\")",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "    result = subprocess.run()",
            ],
            theirsLines: [
                "header",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "if not github_ok and not tuna_ok:",
                "    logger.warning(\"skip\")",
                "podfile_path = project_root / \"Podfile\"",
                "try:",
                "    result = subprocess.run()",
            ],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        XCTAssertEqual(sides.markers.first?.theirsRange, 3..<3)
        XCTAssertEqual(sides.markers.first?.currentLines, ["ours-only"])
        XCTAssertEqual(sides.markers.first?.baseLines, ["base-only"])
        XCTAssertEqual(sides.markers.first?.incomingLines, [])
    }
}
