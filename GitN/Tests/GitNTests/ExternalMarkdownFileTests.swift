import XCTest
@testable import GitN

final class ExternalMarkdownFileTests: XCTestCase {
    func testAcceptsOnlyLocalMarkdownExtensions() {
        for name in ["notes.md", "中文.MD", "notes.markdown", "notes.MDOWN"] {
            XCTAssertTrue(ExternalMarkdownFile.supports(URL(fileURLWithPath: "/tmp/\(name)")))
        }
        for name in ["notes.md.txt", "README", "notes.pdf"] {
            XCTAssertFalse(ExternalMarkdownFile.supports(URL(fileURLWithPath: "/tmp/\(name)")))
        }
        XCTAssertFalse(ExternalMarkdownFile.supports(URL(string: "https://example.com/notes.md")!))
    }

    func testReadsUnicodeAndEmptyDocumentsOutsideRepositories() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("外部 文档.md")
            for text in ["# 标题 🌱\n\n正文\n", ""] {
                try text.write(to: url, atomically: true, encoding: .utf8)
                XCTAssertEqual(try ExternalMarkdownFile.read(url), text)
            }
        }
    }

    func testReadsUTF8BOM() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("bom.md")
            try Data([0xef, 0xbb, 0xbf] + Array("# Title".utf8)).write(to: url)
            XCTAssertEqual(try ExternalMarkdownFile.read(url), "# Title")
        }
    }

    func testRejectsMissingDirectoriesUnsupportedAndInvalidUTF8() throws {
        try withDirectory { directory in
            XCTAssertThrowsError(try ExternalMarkdownFile.read(directory.appendingPathComponent("missing.md")))
            let folder = directory.appendingPathComponent("folder.md", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            XCTAssertThrowsError(try ExternalMarkdownFile.read(folder))
            let invalid = directory.appendingPathComponent("invalid.md")
            try Data([0xff, 0xfe, 0xff]).write(to: invalid)
            XCTAssertThrowsError(try ExternalMarkdownFile.read(invalid))
            XCTAssertThrowsError(try ExternalMarkdownFile.read(directory.appendingPathComponent("file.txt")))
            XCTAssertThrowsError(try ExternalMarkdownFile.read(URL(string: "https://example.com/file.md")!))
        }
    }

    func testCanonicalIdentityResolvesSymlinksAndDotSegments() throws {
        try withDirectory { directory in
            let original = directory.appendingPathComponent("original.md")
            try "# Title".write(to: original, atomically: true, encoding: .utf8)
            let alias = directory.appendingPathComponent("alias.md")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
            XCTAssertEqual(ExternalMarkdownFile.canonicalURL(alias), ExternalMarkdownFile.canonicalURL(original))
            XCTAssertEqual(
                ExternalMarkdownFile.canonicalURL(directory.appendingPathComponent("./original.md")),
                ExternalMarkdownFile.canonicalURL(original)
            )
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
