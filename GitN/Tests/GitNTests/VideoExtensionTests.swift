import XCTest
@testable import GitN

/// Tests for `String.isVideoFile` and the `String.knownVideoExtensions` set.
///
/// These exercise the path-helper boundary directly (no SwiftUI view bodies are
/// instantiated), covering the four required extensions, case-insensitive
/// matching, rejection of non-video extensions, and the no-extension case.
final class VideoExtensionTests: XCTestCase {

    // MARK: - Required extension membership (R1.1)

    func testKnownVideoExtensionsContainsRequiredExtensions() {
        XCTAssertEqual(String.knownVideoExtensions, ["mp4", "m4v", "mov", "m4a"])
    }

    func testRequiredVideoExtensionsMatch() {
        XCTAssertTrue("clip.mp4".isVideoFile)
        XCTAssertTrue("clip.m4v".isVideoFile)
        XCTAssertTrue("clip.mov".isVideoFile)
        XCTAssertTrue("clip.m4a".isVideoFile)
    }

    func testVideoExtensionMatchWithDirectoryPath() {
        XCTAssertTrue("Assets/Movies/intro.mov".isVideoFile)
    }

    // MARK: - Case-insensitive matching (R1.1)

    func testCaseInsensitiveMatch() {
        XCTAssertTrue("Clip.MP4".isVideoFile)
        XCTAssertTrue("Clip.Mp4".isVideoFile)
        XCTAssertTrue("Clip.MOV".isVideoFile)
        XCTAssertTrue("Clip.M4V".isVideoFile)
    }

    // MARK: - Non-video extensions are rejected (R1.1)

    func testNonVideoExtensionsRejected() {
        XCTAssertFalse("a.txt".isVideoFile)
        XCTAssertFalse("a.png".isVideoFile)
        XCTAssertFalse("README.md".isVideoFile)
        XCTAssertFalse("main.swift".isVideoFile)
    }

    // MARK: - No extension returns false (R1.1)

    func testNoExtensionReturnsFalse() {
        XCTAssertFalse("Makefile".isVideoFile)
        XCTAssertFalse("LICENSE".isVideoFile)
        XCTAssertFalse("".isVideoFile)
        XCTAssertFalse("folder/file".isVideoFile)
    }

    // MARK: - VisualFileContent.isVideo flag

    func testVisualFileContentIsVideoFlag() {
        XCTAssertTrue(VisualFileContent(kind: .video, oldData: nil, newData: nil, message: nil).isVideo)
        XCTAssertFalse(VisualFileContent(kind: .image, oldData: nil, newData: nil, message: nil).isVideo)
        XCTAssertFalse(VisualFileContent(kind: .binary, oldData: nil, newData: nil, message: nil).isVideo)
        XCTAssertFalse(VisualFileContent(kind: .text, oldData: nil, newData: nil, message: nil).isVideo)
    }
}
