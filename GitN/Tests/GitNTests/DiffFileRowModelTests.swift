import XCTest
@testable import GitN

/// Tests for the data model properties that drive the right-side diff file list display.
///
/// These tests verify correctness of `DiffFile` model properties and the `String.isImageFile`
/// helper *before* they reach the UI layer. The goal is to catch label/badge inconsistencies
/// (e.g. "renamed image renamed") at the model level rather than relying on visual inspection.
final class DiffFileRowModelTests: XCTestCase {

    // MARK: - DiffFile.isRenamed / isPureRename

    func testIsRenamedIsTrueWhenOldPathIsSet() {
        let file = DiffFile(additions: 0, deletions: 0, path: "new.swift", oldPath: "old.swift", changeKind: .renamed)
        XCTAssertTrue(file.isRenamed)
    }

    func testIsRenamedIsFalseWhenOldPathIsNil() {
        let file = DiffFile(additions: 5, deletions: 2, path: "foo.swift", changeKind: .modified)
        XCTAssertFalse(file.isRenamed)
    }

    func testIsPureRenameIsTrueWhenRenamedWithNoContentChanges() {
        let file = DiffFile(additions: 0, deletions: 0, path: "new.swift", oldPath: "old.swift", changeKind: .renamed)
        XCTAssertTrue(file.isPureRename, "A rename with 0 additions and 0 deletions should be a pure rename")
    }

    func testIsPureRenameIsFalseWhenRenamedWithAdditions() {
        let file = DiffFile(additions: 3, deletions: 0, path: "new.swift", oldPath: "old.swift", changeKind: .renamed)
        XCTAssertFalse(file.isPureRename)
    }

    func testIsPureRenameIsFalseWhenRenamedWithDeletions() {
        let file = DiffFile(additions: 0, deletions: 2, path: "new.swift", oldPath: "old.swift", changeKind: .renamed)
        XCTAssertFalse(file.isPureRename)
    }

    func testIsPureRenameIsFalseWhenNotRenamed() {
        let file = DiffFile(additions: 0, deletions: 0, path: "foo.swift", changeKind: .modified)
        XCTAssertFalse(file.isPureRename)
    }

    // MARK: - String.isImageFile

    func testCommonImageExtensionsAreRecognised() {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "bmp", "ico"] {
            XCTAssertTrue("photo.\(ext)".isImageFile, ".\(ext) should be recognised as an image")
        }
    }

    func testNonImageExtensionsAreNotImageFiles() {
        for ext in ["swift", "txt", "json", "md", "pdf", "zip", "mp4", "mov"] {
            XCTAssertFalse("file.\(ext)".isImageFile, ".\(ext) should not be recognised as an image")
        }
    }

    func testPathWithUppercaseExtensionIsRecognisedAsImage() {
        XCTAssertTrue("Photo.PNG".isImageFile)
        XCTAssertTrue("diagram.JPG".isImageFile)
    }

    func testPathWithNoExtensionIsNotAnImage() {
        XCTAssertFalse("Makefile".isImageFile)
        XCTAssertFalse("".isImageFile)
    }

    // MARK: - Renamed image — "renamed image renamed" bug conditions

    /// A pure-rename of an image file must show only the image status label ("renamed image").
    /// The standalone "renamed" badge must NOT appear alongside it, which would produce
    /// the string "renamed image renamed".
    func testPureRenamedImageFileDoesNotShowRenamedBadge() {
        let file = DiffFile(
            additions: 0,
            deletions: 0,
            path: "icon.png",
            oldPath: "logo.png",
            changeKind: .renamed
        )

        XCTAssertTrue(file.path.isImageFile, "image extension should trigger image status label")
        XCTAssertEqual(file.changeKind, .renamed)
        XCTAssertTrue(file.isPureRename)

        // The image status label already conveys "renamed image"; the separate badge must be suppressed.
        XCTAssertFalse(file.showsRenamedBadge,
            "renamed image should NOT show the 'renamed' text badge — it would produce 'renamed image renamed'")
    }

    func testPureRenameOfTextFileShowsRenamedBadge() {
        let file = DiffFile(
            additions: 0,
            deletions: 0,
            path: "new.swift",
            oldPath: "old.swift",
            changeKind: .renamed
        )

        XCTAssertFalse(file.path.isImageFile)
        XCTAssertTrue(file.isPureRename)
        XCTAssertTrue(file.showsRenamedBadge,
            "a pure-rename text file should show the 'renamed' badge (no image label to replace it)")
    }

    func testRenamedImageWithContentChangesDoesNotShowRenamedBadge() {
        // isPureRename == false (has additions), so showsRenamedBadge is also false.
        let file = DiffFile(
            additions: 2,
            deletions: 0,
            path: "icon.png",
            oldPath: "logo.png",
            changeKind: .renamed
        )

        XCTAssertFalse(file.isPureRename)
        XCTAssertFalse(file.showsRenamedBadge)
    }

    /// Renamed image with content changes: isPureRename is false, so the "renamed" badge won't
    /// fire, leaving only the image status label ("renamed image"). This combination is correct.
    func testRenamedImageWithContentChangesDoesNotMeetPureRenameCondition() {
        let file = DiffFile(
            additions: 4,
            deletions: 0,
            path: "icon.png",
            oldPath: "logo.png",
            changeKind: .renamed
        )

        XCTAssertTrue(file.path.isImageFile)
        XCTAssertEqual(file.changeKind, .renamed)
        XCTAssertFalse(file.isPureRename, "content changes prevent the 'renamed' badge from firing")
        // → only "renamed image" label shows; no duplicate text. This is the desired outcome.
    }

    /// Pure rename of a non-image file: only the "renamed" badge should fire.
    func testPureRenameOfNonImageFileOnlyMeetsPureRenameCondition() {
        let file = DiffFile(
            additions: 0,
            deletions: 0,
            path: "new.swift",
            oldPath: "old.swift",
            changeKind: .renamed
        )

        XCTAssertFalse(file.path.isImageFile, "non-image path should not trigger image label")
        XCTAssertTrue(file.isPureRename, "zero diff lines should show only the 'renamed' badge")
        XCTAssertTrue(file.showsRenamedBadge)
    }

    // MARK: - Image status label conditions for all change kinds

    func testAddedImageMeetsAddedImageCondition() {
        let file = DiffFile(additions: 0, deletions: 0, path: "new.png", changeKind: .added)
        XCTAssertTrue(file.path.isImageFile)
        XCTAssertEqual(file.changeKind, .added)
        XCTAssertFalse(file.isPureRename)
    }

    func testDeletedImageMeetsDeletedImageCondition() {
        let file = DiffFile(additions: 0, deletions: 0, path: "old.png", changeKind: .deleted)
        XCTAssertTrue(file.path.isImageFile)
        XCTAssertEqual(file.changeKind, .deleted)
        XCTAssertFalse(file.isPureRename)
    }

    func testModifiedImageMeetsModifiedImageCondition() {
        let file = DiffFile(additions: 0, deletions: 0, path: "logo.png", changeKind: .modified)
        XCTAssertTrue(file.path.isImageFile)
        XCTAssertEqual(file.changeKind, .modified)
        XCTAssertFalse(file.isPureRename)
    }

    // MARK: - imageStatusText — the label shown in the right-side diff list for image files

    func testModifiedImageStatusTextIsModifiedImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .modified)
        XCTAssertEqual(file.imageStatusText, "modified image")
    }

    func testDeletedImageStatusTextIsMinusImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .deleted)
        XCTAssertEqual(file.imageStatusText, "- image")
    }

    func testAddedImageStatusTextIsPlusImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .added)
        XCTAssertEqual(file.imageStatusText, "+ image")
    }

    func testUntrackedImageStatusTextIsPlusImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .untracked)
        XCTAssertEqual(file.imageStatusText, "+ image")
    }

    func testRenamedImageStatusTextIsRenamedImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", oldPath: "logo.png", changeKind: .renamed)
        XCTAssertEqual(file.imageStatusText, "renamed image")
    }

    func testCopiedImageStatusTextIsCopiedImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .copied)
        XCTAssertEqual(file.imageStatusText, "copied image")
    }

    func testNonImageFileHasNilStatusText() {
        let file = DiffFile(additions: 2, deletions: 1, path: "main.swift", changeKind: .modified)
        XCTAssertNil(file.imageStatusText, "non-image files have no image status label")
    }

    func testModifiedImageStatusTextIsNotMinusImage() {
        let file = DiffFile(additions: 0, deletions: 0, path: "icon.png", changeKind: .modified)
        XCTAssertNotEqual(file.imageStatusText, "- image",
            "modified image must show 'modified image', not '- image' which is reserved for deleted files")
    }

    func testUntrackedImageUsesAddedCondition() {
        let file = DiffFile(additions: 0, deletions: 0, path: "photo.jpg", changeKind: .untracked)
        XCTAssertTrue(file.path.isImageFile)
        XCTAssertEqual(file.changeKind, .untracked)
    }

    // MARK: - FileStatus.diffChangeKind mappings

    func testDiffChangeKindForStagedAdded() {
        let status = FileStatus(statusCode: "A ", path: "new.swift")
        XCTAssertEqual(status.diffChangeKind, .added)
    }

    func testDiffChangeKindForStagedDeleted() {
        let status = FileStatus(statusCode: "D ", path: "gone.swift")
        XCTAssertEqual(status.diffChangeKind, .deleted)
    }

    func testDiffChangeKindForStagedModified() {
        let status = FileStatus(statusCode: "M ", path: "changed.swift")
        XCTAssertEqual(status.diffChangeKind, .modified)
    }

    func testDiffChangeKindForStagedRenamed() {
        let status = FileStatus(statusCode: "R ", path: "renamed.swift")
        XCTAssertEqual(status.diffChangeKind, .renamed)
    }

    func testDiffChangeKindForUntracked() {
        let status = FileStatus(statusCode: "??", path: "untracked.swift")
        XCTAssertEqual(status.diffChangeKind, .untracked)
    }

    func testDiffChangeKindForUnstagedModified() {
        let status = FileStatus(statusCode: " M", path: "changed.swift")
        XCTAssertEqual(status.diffChangeKind, .modified)
    }

    func testDiffChangeKindForUnstagedDeleted() {
        let status = FileStatus(statusCode: " D", path: "gone.swift")
        XCTAssertEqual(status.diffChangeKind, .deleted)
    }

    func testDiffChangeKindForStagedCopied() {
        let status = FileStatus(statusCode: "C ", path: "copy.swift")
        XCTAssertEqual(status.diffChangeKind, .copied)
    }

    // MARK: - FileStatus staged/unstaged status descriptions

    func testStagedDescriptionForAdded() {
        let status = FileStatus(statusCode: "A ", path: "file.swift")
        XCTAssertEqual(status.stagedDescription, "Added")
    }

    func testStagedDescriptionForModified() {
        let status = FileStatus(statusCode: "M ", path: "file.swift")
        XCTAssertEqual(status.stagedDescription, "Modified")
    }

    func testStagedDescriptionForDeleted() {
        let status = FileStatus(statusCode: "D ", path: "file.swift")
        XCTAssertEqual(status.stagedDescription, "Deleted")
    }

    func testStagedDescriptionForRenamed() {
        let status = FileStatus(statusCode: "R ", path: "file.swift")
        XCTAssertEqual(status.stagedDescription, "Renamed")
    }

    func testUnstagedDescriptionForModified() {
        let status = FileStatus(statusCode: " M", path: "file.swift")
        XCTAssertEqual(status.unstagedDescription, "Modified")
    }

    func testUnstagedDescriptionForDeleted() {
        let status = FileStatus(statusCode: " D", path: "file.swift")
        XCTAssertEqual(status.unstagedDescription, "Deleted")
    }

    func testUnstagedDescriptionForUntracked() {
        let status = FileStatus(statusCode: "??", path: "file.swift")
        XCTAssertEqual(status.unstagedDescription, "Untracked")
    }

    // MARK: - DiffFile identity

    func testDiffFileIDIsPath() {
        let file = DiffFile(additions: 1, deletions: 0, path: "src/foo.swift", changeKind: .modified)
        XCTAssertEqual(file.id, "src/foo.swift")
    }

    func testDiffFileIDIsNewPathForRenames() {
        let file = DiffFile(additions: 0, deletions: 0, path: "new/bar.swift", oldPath: "old/bar.swift", changeKind: .renamed)
        XCTAssertEqual(file.id, "new/bar.swift", "id should be the new path after rename")
    }
}
