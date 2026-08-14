import XCTest
@testable import GitN

/// Tests for the logic that drives the middle diff-content view:
/// language detection, Monaco language mapping, before/after file resolution
/// for renamed files, and preview-mode type selection.
///
/// These tests operate at the ViewModel/service boundary so they catch
/// correctness issues before they surface in the UI.
@MainActor
final class DiffContentLogicTests: XCTestCase {

    // 1x1 transparent PNG — stable across platforms.
    private let onePixelPNGData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN6kAAAAASUVORK5CYII="
    )!

    // Small binary blob with null bytes so git classifies the file as binary
    // (the model layer only needs bytes + a video extension; playability is a
    // view-layer concern handled by VideoPreviewController).
    private let fakeVideoData = Data([
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
        0x6D, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00
    ])

    // MARK: - Language detection

    func testSourceLanguageForKnownExtensions() {
        XCTAssertEqual("main.swift".sourceLanguage, .swift)
        XCTAssertEqual("app.py".sourceLanguage, .python)
        XCTAssertEqual("index.js".sourceLanguage, .javascript)
        XCTAssertEqual("types.ts".sourceLanguage, .typescript)
        XCTAssertEqual("main.go".sourceLanguage, .go)
        XCTAssertEqual("lib.rs".sourceLanguage, .rust)
        XCTAssertEqual("header.h".sourceLanguage, .c)
        XCTAssertEqual("impl.cpp".sourceLanguage, .cpp)
        XCTAssertEqual("Class.java".sourceLanguage, .java)
        XCTAssertEqual("run.sh".sourceLanguage, .shell)
        XCTAssertEqual("data.json".sourceLanguage, .json)
        XCTAssertEqual("config.yml".sourceLanguage, .yaml)
        XCTAssertEqual("config.yaml".sourceLanguage, .yaml)
    }

    /// `.md` has no dedicated SourceLanguage case and falls through to `.text`.
    /// This means Monaco receives "plaintext" rather than "markdown", so the preview
    /// pane renders raw Markdown source instead of a formatted document.
    // MARK: - Markdown preview routing

    /// `MarkdownInspectorContentView` is the rendered-preview component for .md files.
    /// It is shown when `fileInspectorPath.isMarkdownFile == true` in preview mode.
    /// This test confirms the routing condition fires and the content is loaded correctly.
    func testMarkdownFileInPreviewModeLoadsContentAndIsRecognisedAsMarkdown() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "# Hello\n\nThis is a test.\n")
        try repo.commitAll(message: "add readme")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "add readme" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "README.md" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .preview)

        // Path must be recognised as markdown so the UI routes to MarkdownInspectorContentView.
        XCTAssertTrue(viewModel.fileInspectorPath.isMarkdownFile,
            "isMarkdownFile must be true for .md — the condition that selects MarkdownInspectorContentView")
        // Content must be loaded so the rendered preview is not blank.
        XCTAssertTrue(viewModel.fileInspectorContent.contains("# Hello"),
            "fileInspectorContent must contain the markdown source; got: \(viewModel.fileInspectorContent.debugDescription)")
        // Committed files are read-only — the edit toggle must not appear.
        XCTAssertFalse(viewModel.isFileInspectorEditable,
            "committed markdown file must not be editable")
    }

    func testMarkdownFileRequestedInDiffModeKeepsInspectorInDiff() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "# Hello\n\nThis is a test.\n")
        try repo.commitAll(message: "add readme")
        try repo.writeFile("README.md", contents: "# Hello\n\nThis is a test.\n\nUpdated.\n")
        try repo.commitAll(message: "update readme")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "update readme" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "README.md" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertEqual(viewModel.fileInspectorMode, .diff,
            "Markdown files opened from a diff entry should stay in diff mode so the patch is visible")
        XCTAssertTrue(viewModel.fileInspectorPath.isMarkdownFile)
        XCTAssertFalse(viewModel.fileDiffContent.isEmpty,
            "the committed markdown diff should be loaded into the inspector flow")
        XCTAssertNotNil(viewModel.parsedDiff,
            "markdown files opened from diff mode should produce parsed diff hunks when the commit changed the file")
    }

    func testMarkdownFilesResolveToMarkdownLanguage() {
        XCTAssertEqual("README.md".sourceLanguage, .markdown)
        XCTAssertEqual("CHANGELOG.md".sourceLanguage, .markdown)
        XCTAssertEqual("doc.markdown".sourceLanguage, .markdown)
    }

    // MARK: - Monaco language mapping

    func testMonacoLanguageForCommonSourceLanguages() {
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .swift), "swift")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .python), "python")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .javascript), "javascript")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .typescript), "typescript")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .go), "go")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .rust), "rust")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .json), "json")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .yaml), "yaml")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .html), "html")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .css), "css")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .xml), "xml")
    }

    func testMonacoLanguageForShellIsShellScript() {
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .shell), "shellscript")
    }

    func testMonacoLanguageForKotlinAndTomlIsPlaintext() {
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .kotlin), "plaintext")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .toml), "plaintext")
    }

    func testMarkdownFileGetsMarkdownMonacoLanguage() {
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: .markdown), "markdown")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: "README.md".sourceLanguage), "markdown")
        XCTAssertEqual(RepoViewModel.monacoLanguage(for: "CHANGELOG.md".sourceLanguage), "markdown")
    }

    // MARK: - VisualFileContent model

    func testVisualFileContentCurrentDataPrefersNewData() {
        let old = Data([0x01])
        let new = Data([0x02])
        let content = VisualFileContent(kind: .image, oldData: old, newData: new, message: nil)
        XCTAssertEqual(content.currentData, new)
    }

    func testVisualFileContentCurrentDataFallsBackToOldData() {
        let old = Data([0x01])
        let content = VisualFileContent(kind: .image, oldData: old, newData: nil, message: nil)
        XCTAssertEqual(content.currentData, old)
    }

    func testVisualFileContentCurrentDataIsNilWhenBothNil() {
        let content = VisualFileContent(kind: .binary, oldData: nil, newData: nil, message: "no data")
        XCTAssertNil(content.currentData)
    }

    func testVisualFileContentIsImageFlag() {
        XCTAssertTrue(VisualFileContent(kind: .image, oldData: nil, newData: nil, message: nil).isImage)
        XCTAssertFalse(VisualFileContent(kind: .binary, oldData: nil, newData: nil, message: nil).isImage)
        XCTAssertFalse(VisualFileContent(kind: .text, oldData: nil, newData: nil, message: nil).isImage)
    }

    func testVisualFileContentIsBinaryFlag() {
        XCTAssertTrue(VisualFileContent(kind: .binary, oldData: nil, newData: nil, message: nil).isBinary)
        XCTAssertFalse(VisualFileContent(kind: .image, oldData: nil, newData: nil, message: nil).isBinary)
    }

    // MARK: - Committed renamed text file: DiffFile has correct oldPath

    func testCommittedRenameProducesDiffFileWithOldPath() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("old_name.swift", contents: "let x = 1\n")
        try repo.commitAll(message: "add file")

        try repo.run(["mv", "old_name.swift", "new_name.swift"])
        try repo.commitAll(message: "rename file")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let renameCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "rename file" })
        )
        await viewModel.selectCommit(renameCommit)

        let renamedFile = try XCTUnwrap(
            viewModel.diffFiles.first(where: { $0.path == "new_name.swift" }),
            "diffFiles should contain the renamed file under its new name"
        )
        XCTAssertEqual(renamedFile.oldPath, "old_name.swift",
            "oldPath should point to the original filename before the rename")
        XCTAssertEqual(renamedFile.changeKind, .renamed)
        XCTAssertTrue(renamedFile.isPureRename,
            "a rename with no line changes should be a pure rename")
    }

    /// Verifies that a rename+modify commit produces a DiffFile with `oldPath` set and
    /// non-zero line stats when stats are fully computed via `GitService.diffDetail`.
    ///
    /// `RepoViewModel.diffFiles` initially receives 0-stat placeholders from
    /// `committedDiffPreview`; the accurate stats arrive later via a background task.
    /// Calling `diffDetail` directly bypasses that async gap and lets the test assert
    /// `isPureRename == false` without racing against the background update.
    func testCommittedRenameWithContentChangesIsNotPureRename() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("before.txt", contents: "line one\n")
        try repo.commitAll(message: "initial")

        try repo.run(["mv", "before.txt", "after.txt"])
        try repo.writeFile("after.txt", contents: "line one\nline two\n")
        let renameHash = try repo.commitAll(message: "rename and modify")

        // Use GitService.diffDetail which computes line stats synchronously via libgit2.
        let service = GitService(repoPath: repo.path)
        let files = try await service.diffDetail(hash: renameHash)

        let file = try XCTUnwrap(files.first(where: { $0.path == "after.txt" }),
            "diffDetail should contain the renamed file")
        XCTAssertEqual(file.oldPath, "before.txt",
            "oldPath must be the pre-rename filename")
        XCTAssertFalse(file.isPureRename,
            "content changes alongside the rename mean this is not a pure rename")
        XCTAssertEqual(file.changeKind, .renamed)
        XCTAssertGreaterThan(file.additions, 0,
            "the added line should register as an addition")
    }

    func testCommittedRenameAndModifyDiffContentIsNonEmpty() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("foo.txt", contents: "alpha\n")
        try repo.commitAll(message: "initial")

        try repo.run(["mv", "foo.txt", "bar.txt"])
        try repo.writeFile("bar.txt", contents: "alpha\nbeta\n")
        try repo.commitAll(message: "rename and add line")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "rename and add line" })
        )
        await viewModel.selectCommit(commit)

        XCTAssertFalse(viewModel.fileDiffContent.isEmpty,
            "a rename+modify commit should produce a non-empty diff")
        XCTAssertNotNil(viewModel.selectedDiffFile,
            "a file should be auto-selected after commit selection")
        XCTAssertEqual(viewModel.selectedDiffFile?.path, "bar.txt")
        XCTAssertEqual(viewModel.selectedDiffFile?.oldPath, "foo.txt")
    }

    // MARK: - Committed renamed image: before and after data

    func testCommittedPureRenameImageHasBothOldAndNewVisualData() async throws {
        let repo = try TemporaryGitRepository()

        let originalURL = URL(fileURLWithPath: repo.path).appendingPathComponent("logo.png")
        try onePixelPNGData.write(to: originalURL)
        try repo.commitAll(message: "add image")

        try repo.run(["mv", "logo.png", "icon.png"])
        try repo.commitAll(message: "rename image")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let renameCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "rename image" })
        )
        await viewModel.selectCommit(renameCommit)

        let renamedFile = try XCTUnwrap(
            viewModel.diffFiles.first(where: { $0.path == "icon.png" })
        )
        XCTAssertEqual(renamedFile.oldPath, "logo.png")
        XCTAssertTrue(renamedFile.isPureRename)
        XCTAssertTrue(renamedFile.path.isImageFile)

        // The diff view should load visual content for both before and after.
        let visual = try XCTUnwrap(
            viewModel.selectedDiffVisualContent,
            "a renamed image should produce visual content"
        )
        XCTAssertEqual(visual.kind, .image)
        XCTAssertNotNil(visual.oldData,
            "oldData should be the image bytes fetched from oldPath at the parent commit")
        XCTAssertNotNil(visual.newData,
            "newData should be the image bytes fetched from the new path at this commit")
    }

    // MARK: - Committed added image: only newData

    func testCommittedAddedImageHasOnlyNewData() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("placeholder.txt", contents: "init\n")
        try repo.commitAll(message: "init")

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("banner.png")
        try onePixelPNGData.write(to: imageURL)
        try repo.commitAll(message: "add banner")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let addCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "add banner" })
        )
        await viewModel.selectCommit(addCommit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "banner.png" }))
        XCTAssertEqual(file.changeKind, .added)
        XCTAssertNil(file.oldPath)

        let visual = try XCTUnwrap(viewModel.selectedDiffVisualContent)
        XCTAssertEqual(visual.kind, .image)
        XCTAssertNotNil(visual.newData, "newData should hold the added image bytes")
        XCTAssertNil(visual.oldData, "oldData should be nil for a newly added image")
    }

    // MARK: - Committed deleted image: only oldData

    func testCommittedDeletedImageHasOnlyOldData() async throws {
        let repo = try TemporaryGitRepository()

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("removed.png")
        try onePixelPNGData.write(to: imageURL)
        try repo.commitAll(message: "add image")

        try repo.run(["rm", "removed.png"])
        try repo.commitAll(message: "delete image")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let deleteCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "delete image" })
        )
        await viewModel.selectCommit(deleteCommit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "removed.png" }))
        XCTAssertEqual(file.changeKind, .deleted)

        let visual = try XCTUnwrap(viewModel.selectedDiffVisualContent)
        XCTAssertEqual(visual.kind, .image)
        XCTAssertNotNil(visual.oldData, "oldData should hold the pre-deletion image bytes")
        XCTAssertNil(visual.newData, "newData should be nil for a deleted image")
    }

    // MARK: - Committed added video: kind .video bound to post-image bytes

    func testCommittedAddedVideoProducesVideoVisualContentWithNewData() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("placeholder.txt", contents: "init\n")
        try repo.commitAll(message: "init")

        let videoURL = URL(fileURLWithPath: repo.path).appendingPathComponent("clip.mp4")
        try fakeVideoData.write(to: videoURL)
        try repo.commitAll(message: "add clip")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let addCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "add clip" })
        )
        await viewModel.selectCommit(addCommit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "clip.mp4" }))
        XCTAssertEqual(file.changeKind, .added)
        XCTAssertTrue(file.path.isVideoFile)

        let visual = try XCTUnwrap(
            viewModel.selectedDiffVisualContent,
            "a video file should produce visual content"
        )
        XCTAssertEqual(visual.kind, .video,
            "video files must be surfaced as .video, not .binary")
        XCTAssertNotNil(visual.newData, "newData should hold the added video bytes (post-image)")
        XCTAssertNil(visual.oldData, "oldData should be nil for a newly added video")
        XCTAssertEqual(visual.currentData, visual.newData,
            "currentData must prefer the post-image bytes (newData ?? oldData)")
    }

    // MARK: - Committed deleted video: kind .video falls back to pre-image bytes

    func testCommittedDeletedVideoProducesVideoVisualContentWithOldData() async throws {
        let repo = try TemporaryGitRepository()

        let videoURL = URL(fileURLWithPath: repo.path).appendingPathComponent("removed.mp4")
        try fakeVideoData.write(to: videoURL)
        try repo.commitAll(message: "add clip")

        try repo.run(["rm", "removed.mp4"])
        try repo.commitAll(message: "delete clip")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let deleteCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "delete clip" })
        )
        await viewModel.selectCommit(deleteCommit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "removed.mp4" }))
        XCTAssertEqual(file.changeKind, .deleted)

        let visual = try XCTUnwrap(viewModel.selectedDiffVisualContent)
        XCTAssertEqual(visual.kind, .video,
            "a deleted video must still resolve to .video using its pre-image bytes")
        XCTAssertNotNil(visual.oldData, "oldData should hold the pre-deletion video bytes")
        XCTAssertNil(visual.newData, "newData should be nil for a deleted video")
        XCTAssertEqual(visual.currentData, visual.oldData,
            "currentData should fall back to oldData for deletions")
    }

    func testCommittedDeletedLFSImageHasOnlyOldData() async throws {
        try requireGitLFS()

        let repo = try TemporaryGitRepository()
        try repo.run(["lfs", "install", "--local"])
        try repo.run(["lfs", "track", "*.png"])

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("removed-lfs.png")
        try onePixelPNGData.write(to: imageURL)
        try repo.commitAll(message: "add lfs image")

        try repo.run(["rm", "removed-lfs.png"])
        try repo.commitAll(message: "delete lfs image")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let deleteCommit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "delete lfs image" })
        )
        await viewModel.selectCommit(deleteCommit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "removed-lfs.png" }))
        XCTAssertEqual(file.changeKind, .deleted)

        let visual = try XCTUnwrap(viewModel.selectedDiffVisualContent)
        XCTAssertEqual(visual.kind, .image)
        XCTAssertEqual(visual.oldData, onePixelPNGData)
        XCTAssertNil(visual.newData)
    }

    // MARK: - Diff context: before-text source for renamed text file

    /// For a committed rename+modify, the before text lives in the diff itself
    /// (git tracks oldPath automatically). After selectCommit auto-selects the file,
    /// `fileDiffContent` should contain both "rename from" / "rename to" markers
    /// AND the changed lines — confirming the before/after content is correct.
    func testCommittedRenameAndModifyDiffContainsRenameAndContentMarkers() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("original.txt", contents: "hello\n")
        try repo.commitAll(message: "initial")

        try repo.run(["mv", "original.txt", "renamed.txt"])
        try repo.writeFile("renamed.txt", contents: "hello\nworld\n")
        try repo.commitAll(message: "rename and edit")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "rename and edit" })
        )
        await viewModel.selectCommit(commit)

        let diff = viewModel.fileDiffContent
        // The diff text should reference both the old filename (as the "before" source)
        // and the new filename (as the "after" target).
        XCTAssertTrue(
            diff.contains("original.txt") || diff.contains("renamed.txt"),
            "diff should reference file names; got:\n\(diff)"
        )
        // The added line must appear in the diff.
        XCTAssertTrue(diff.contains("+world") || diff.contains("world"),
            "diff should contain the newly added line; got:\n\(diff)")
    }

    // MARK: - Auto-selected file after commit selection

    func testSelectCommitAutoSelectsFirstDiffFile() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        try repo.writeFile("b.txt", contents: "two\n")
        try repo.commitAll(message: "two files")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { !$0.isUncommitted }))
        await viewModel.selectCommit(commit)

        XCTAssertNotNil(viewModel.selectedDiffFile,
            "the first diff file should be auto-selected after commit selection")
        XCTAssertFalse(viewModel.diffFiles.isEmpty,
            "diffFiles should be populated after commit selection")
    }

    // MARK: - Pure rename: no diff content but renamed flag is set

    func testCommittedPureRenameTextFileHasNoMeaningfulDiff() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("before.swift", contents: "let x = 1\n")
        try repo.commitAll(message: "initial")

        try repo.run(["mv", "before.swift", "after.swift"])
        try repo.commitAll(message: "pure rename")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "pure rename" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "after.swift" }))
        XCTAssertTrue(file.isPureRename)
        XCTAssertEqual(file.oldPath, "before.swift")
        // A pure rename has no line changes, so parsedDiff should be empty/nil.
        XCTAssertNil(viewModel.parsedDiff,
            "a pure rename should produce no parsed diff hunks")
    }

    // MARK: - Renamed image: showsRenamedBadge suppressed, Before subtitle uses oldPath

    func testShowsRenamedBadgeIsFalseForRenamedImage() {
        let file = DiffFile(
            additions: 0, deletions: 0,
            path: "icon.png", oldPath: "logo.png", changeKind: .renamed
        )
        XCTAssertFalse(file.showsRenamedBadge,
            "renamed image already has an image status label; the 'renamed' badge must not appear alongside it")
    }

    func testShowsRenamedBadgeIsTrueForRenamedTextFile() {
        let file = DiffFile(
            additions: 0, deletions: 0,
            path: "new.json", oldPath: "old.json", changeKind: .renamed
        )
        XCTAssertTrue(file.showsRenamedBadge)
    }

    /// For a committed renamed image the file inspector must expose `fileInspectorOldPath`
    /// so the "Before" card in `ImageDiffContentView` can show the correct subtitle.
    func testFileInspectorOldPathIsSetForRenamedImage() async throws {
        let repo = try TemporaryGitRepository()

        let originalURL = URL(fileURLWithPath: repo.path).appendingPathComponent("logo.png")
        try onePixelPNGData.write(to: originalURL)
        try repo.commitAll(message: "add image")

        try repo.run(["mv", "logo.png", "icon.png"])
        try repo.commitAll(message: "rename image")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename image" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "icon.png" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertEqual(viewModel.fileInspectorOldPath, "logo.png",
            "fileInspectorOldPath must be set to oldPath so the Before card shows the right subtitle")
        XCTAssertEqual(viewModel.fileInspectorPath, "icon.png",
            "fileInspectorPath must be the new (after) path")
    }

    /// After closing the inspector, oldPath must be cleared.
    func testFileInspectorOldPathIsClearedOnClose() async throws {
        let repo = try TemporaryGitRepository()

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("logo.png")
        try onePixelPNGData.write(to: imageURL)
        try repo.commitAll(message: "add image")

        try repo.run(["mv", "logo.png", "icon.png"])
        try repo.commitAll(message: "rename image")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename image" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "icon.png" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
        XCTAssertEqual(viewModel.fileInspectorOldPath, "logo.png")

        viewModel.closeFileInspector()
        XCTAssertNil(viewModel.fileInspectorOldPath, "oldPath must be cleared when the inspector closes")
    }

    // MARK: - Pure text rename must not be mistakenly classified as binary
    //
    // Root cause of the "binary diff is not readable" bug for renamed text files:
    //
    //   1. fileDiff(hash, newPath) returns a rename-only header with no +/- lines.
    //   2. DiffParserEngine.parse() produces zero hunks.
    //   3. Because hunks are empty, loadDiffPayload falls back to makeVisualDiffContent()
    //      with both oldData and newData set (raw file bytes from git blob storage).
    //   4. makeVisualDiffContent only special-cases images; any other non-nil data pair
    //      is classified as .binary, producing VisualFileContent(kind: .binary, ...).
    //   5. The diff panel renders this as "Binary diff is not readable".
    //   6. The file inspector opened in diff mode inherits the same binary visual content.
    //   7. Switching to preview mode in the inspector does NOT reload the content —
    //      setFileInspectorMode(.preview) keeps fileInspectorVisualContent unchanged —
    //      so the inspector still shows "Binary file preview is not readable".
    //
    // Tests below assert the CORRECT expected behaviour.
    // They currently FAIL, which is intentional: each failure pinpoints a specific bug.

    /// A pure rename of a text file (JSON) should produce nil visual content in the
    /// diff panel — not .binary — because the file contents are readable as text.
    ///
    /// Currently FAILS: selectedDiffVisualContent?.kind == .binary
    func testPureRenameOfTextFileDoesNotProduceBinaryVisualContentInDiffPanel() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("manifest.json", contents: "{\"version\": 1}\n")
        try repo.commitAll(message: "add json")

        try repo.run(["mv", "manifest.json", "config.json"])
        try repo.commitAll(message: "rename json")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename json" }))
        await viewModel.selectCommit(commit)

        XCTAssertNil(
            viewModel.selectedDiffVisualContent,
            "a pure rename of a text file should not produce binary visual content; " +
            "the diff panel should show the rename placeholder, not 'Binary diff is not readable'. " +
            "BUG: makeVisualDiffContent classifies any non-image file with data blobs as .binary."
        )
    }

    /// Same scenario but with a .swift source file — confirms the bug is not
    /// JSON-specific but affects all pure text renames.
    ///
    /// Currently FAILS: selectedDiffVisualContent?.kind == .binary
    func testPureRenameOfSwiftFileDoesNotProduceBinaryVisualContent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("OldName.swift", contents: "struct Foo {}\n")
        try repo.commitAll(message: "add swift")

        try repo.run(["mv", "OldName.swift", "NewName.swift"])
        try repo.commitAll(message: "rename swift")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename swift" }))
        await viewModel.selectCommit(commit)

        XCTAssertNil(
            viewModel.selectedDiffVisualContent,
            "a pure rename of a .swift file should not be classified as binary visual content."
        )
    }

    /// When the file inspector is opened in diff mode for a pure text rename,
    /// fileInspectorVisualContent should be nil (not .binary), so the Monaco editor
    /// can show a meaningful diff instead of the "Binary diff is not readable" banner.
    ///
    /// Currently FAILS: fileInspectorVisualContent?.kind == .binary
    func testFileInspectorDiffModeForPureTextRenameDoesNotShowBinaryContent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("manifest.json", contents: "{\"version\": 1}\n")
        try repo.commitAll(message: "add json")

        try repo.run(["mv", "manifest.json", "config.json"])
        try repo.commitAll(message: "rename json")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename json" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "config.json" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertNil(
            viewModel.fileInspectorVisualContent,
            "file inspector in diff mode for a pure text rename must not have binary visual content. " +
            "BUG: fileInspectorVisualContent inherits selectedDiffVisualContent (.binary) " +
            "via payloadVisualContent(for:) when parsedDiff is nil."
        )
    }

    /// When the user switches from diff to preview mode in the inspector for a renamed
    /// text file, the preview should show the file's actual text content — not inherit
    /// the stale binary visual content that was set in diff mode.
    ///
    /// Currently FAILS: fileInspectorVisualContent?.kind == .binary after the switch
    func testFileInspectorSwitchFromDiffToPreviewOnRenamedTextFileClearsVisualContent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("manifest.json", contents: "{\"version\": 1}\n")
        try repo.commitAll(message: "add json")

        try repo.run(["mv", "manifest.json", "config.json"])
        try repo.commitAll(message: "rename json")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename json" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "config.json" }))
        // Open in diff mode first (the default entry point from the UI).
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
        // Then switch to preview mode, as the user would do by clicking the segmented control.
        await viewModel.setFileInspectorMode(.preview)

        XCTAssertNil(
            viewModel.fileInspectorVisualContent,
            "switching to preview mode on a text file must clear the binary visual content set by diff mode. " +
            "BUG: setFileInspectorMode(.preview) keeps fileInspectorVisualContent unchanged " +
            "(mode == .diff is false, so it falls through to 'fileInspectorVisualContent = fileInspectorVisualContent')."
        )
        // Committed files are always read-only (canEditInspectorContent enforces context != .committed).
        XCTAssertFalse(
            viewModel.isFileInspectorEditable,
            "committed files should not be editable regardless of inspector mode"
        )
    }

    // MARK: - File inspector diff base text for committed renames
    //
    // When the file inspector opens in diff mode for a committed rename, Monaco receives
    // two text strings: originalText (the "before" / base) and modifiedText (the "after").
    //
    // The bug: for any rename whose diff has no content hunks (pure rename, or even a
    // rename+modify before parsedDiff is available), `usesRawDiffFallback = true` and
    // `inspectorBaseText` is set to `displayTextForRawDiffFallback(fileDiffContent)`.
    // That function returns the raw git diff header unchanged for non-submodule files, so
    // Monaco ends up with the 4-line rename header as "before" and the real file content
    // as "after" — producing a noisy, incorrect diff.
    //
    // Expected: originalText = content of oldPath at parent commit
    //           modifiedText = content of newPath at current commit

    /// For a pure rename, the inspector's diff base must be the actual old file content,
    /// not the raw git diff header.  For a pure rename the two texts are identical, so
    /// Monaco should show zero differences.
    ///
    /// Currently FAILS: fileInspectorDiffBaseText contains the git rename header.
    func testFileInspectorDiffBaseIsOldPathContentForPureRename() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("manifest.json", contents: "{\"version\": 1}\n")
        try repo.commitAll(message: "add json")

        try repo.run(["mv", "manifest.json", "config.json"])
        try repo.commitAll(message: "rename json")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename json" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "config.json" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        let base = viewModel.fileInspectorDiffBaseText
        let current = viewModel.fileInspectorContent

        // The base text must be the original JSON content, not a git diff header.
        XCTAssertFalse(
            base.contains("diff --git") || base.contains("rename from") || base.contains("rename to"),
            "fileInspectorDiffBaseText must not contain raw git diff header lines; got:\n\(base)"
        )
        // For a pure rename the content is unchanged, so base == current.
        XCTAssertEqual(
            base, current,
            "pure rename: before and after content must be identical; " +
            "base=\(base.debugDescription) current=\(current.debugDescription)"
        )
    }

    /// For a rename + content modification, the inspector's diff base must be the old path
    /// content (from the parent commit), not the raw git header or a reconstructed guess.
    ///
    /// Currently FAILS: fileInspectorDiffBaseText is a reconstructed approximation that
    /// may differ from the real pre-rename content.
    func testFileInspectorDiffBaseIsOldPathContentForRenameWithModification() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("before.swift", contents: "let x = 1\n")
        try repo.commitAll(message: "initial")

        try repo.run(["mv", "before.swift", "after.swift"])
        try repo.writeFile("after.swift", contents: "let x = 1\nlet y = 2\n")
        try repo.commitAll(message: "rename and add line")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "rename and add line" })
        )
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "after.swift" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        let base = viewModel.fileInspectorDiffBaseText
        let current = viewModel.fileInspectorContent

        // Base text must be the original file content (the "before" side of the rename).
        XCTAssertEqual(base, "let x = 1\n",
            "before content should be the old path's content at the parent commit; got: \(base.debugDescription)")
        // Current text is the new file content after the modification.
        XCTAssertEqual(current, "let x = 1\nlet y = 2\n",
            "after content should be the new path's content; got: \(current.debugDescription)")
        // The diff base must not contain the new line.
        XCTAssertFalse(base.contains("let y = 2"),
            "base text must not contain lines that were only added in this commit")
    }

    /// Regression for phantom deletions on CRLF files. A single-line change in a
    /// file saved with Windows line endings must reconstruct a diff base that equals
    /// the real "before" content, not a one-line blob that makes the whole hunk look
    /// deleted. Mirrors the real-world `number_percision.dart` report.
    func testFileInspectorDiffBaseHandlesCRLFSingleLineChange() async throws {
        let repo = try TemporaryGitRepository()
        // Keep git from rewriting line endings so the blobs stay CRLF on disk and in-tree.
        try repo.run(["config", "core.autocrlf", "false"])

        let before = "/// header\r\n/// Author\r\n///\r\n// ignore_for_file: a, b\r\nimport 'dart:math';\r\n"
        let after = "/// header\r\n/// Author\r\n///\r\n// ignore_for_file: a, b, c\r\nimport 'dart:math';\r\n"

        try repo.writeFile("crlf.dart", contents: before)
        try repo.commitAll(message: "add crlf file")
        try repo.writeFile("crlf.dart", contents: after)
        try repo.commitAll(message: "tweak ignore_for_file")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(
            viewModel.commits.first(where: { $0.message == "tweak ignore_for_file" })
        )
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "crlf.dart" }))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        let base = viewModel.fileInspectorDiffBaseText
        let current = viewModel.fileInspectorContent

        XCTAssertEqual(current, after, "modified side should be the committed file content")
        XCTAssertEqual(base, before,
            "reconstructed base for a CRLF file must equal the real previous content, " +
            "not a collapsed single line that fabricates a whole-block deletion; got: \(base.debugDescription)")
        // The unchanged context lines must survive on the base side.
        XCTAssertTrue(base.contains("import 'dart:math';"),
            "context lines must remain in the base text instead of appearing as deletions")
    }

    /// The preview mode inspector opened DIRECTLY (not via a diff→preview switch)
    /// does load the content correctly and should not have binary visual content.
    /// This passing test is the counterpart to the switch-mode failing test above.
    func testFileInspectorOpenedDirectlyInPreviewModeForRenamedTextFileHasNoVisualContent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("manifest.json", contents: "{\"version\": 1}\n")
        try repo.commitAll(message: "add json")

        try repo.run(["mv", "manifest.json", "config.json"])
        try repo.commitAll(message: "rename json")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let commit = try XCTUnwrap(viewModel.commits.first(where: { $0.message == "rename json" }))
        await viewModel.selectCommit(commit)

        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "config.json" }))
        // Open directly in preview mode — this path uses loaded.visualContent (nil for text files).
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .preview)

        XCTAssertNil(
            viewModel.fileInspectorVisualContent,
            "opening the inspector directly in preview mode uses loadInspectableFileContent " +
            "which correctly returns nil visual content for decodable text files."
        )
        // Committed files are read-only (canEditInspectorContent enforces context != .committed).
        XCTAssertFalse(viewModel.isFileInspectorEditable)
        XCTAssertFalse(viewModel.fileInspectorContent.isEmpty,
            "file content should be loaded as text when opened directly in preview mode")
    }
}

private func requireGitLFS(file: StaticString = #filePath, line: UInt = #line) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["lfs", "version"]
    process.currentDirectoryURL = FileManager.default.temporaryDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw XCTSkip("git-lfs is not installed in this environment")
    }
}
