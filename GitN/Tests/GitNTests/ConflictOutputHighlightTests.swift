import AppKit
import XCTest
@testable import GitN

final class ConflictOutputHighlightTests: XCTestCase {
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func testEditedLineHighlightPreservesUntouchedAttributes() {
        let original = "let head = 1\nlet tail = 2\n"
        let storage = NSTextStorage(attributedString:
            ConflictOutputEditorView.highlightedText(original, filePath: "code.swift", font: font)
        )
        storage.addAttribute(.backgroundColor, value: NSColor.systemTeal,
                             range: NSRange(location: 0, length: 3))
        let edit = (storage.string as NSString).range(of: "tail")
        storage.replaceCharacters(in: edit, with: "other")

        ConflictOutputEditorView.highlightEditedLines(
            in: storage,
            editedRange: NSRange(location: edit.location, length: 5),
            filePath: "code.swift",
            font: font
        )

        XCTAssertEqual(storage.string, "let head = 1\nlet other = 2\n")
        XCTAssertEqual(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       .systemTeal)
        let secondLet = (storage.string as NSString).range(of: "let", options: [],
                                                            range: NSRange(location: 4, length: storage.length - 4))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: secondLet.location,
                                         effectiveRange: nil) as? NSColor, .systemPink)
    }

    func testInsertedNewlineStylesNewLogicalLine() {
        let storage = NSTextStorage(attributedString:
            ConflictOutputEditorView.highlightedText("let a = 1\nlet b = 2", filePath: "code.swift", font: font)
        )
        let insertion = (storage.string as NSString).range(of: "let b").location
        storage.replaceCharacters(in: NSRange(location: insertion, length: 0), with: "\n")

        ConflictOutputEditorView.highlightEditedLines(
            in: storage, editedRange: NSRange(location: insertion, length: 1),
            filePath: "code.swift", font: font
        )

        XCTAssertEqual(storage.string, "let a = 1\n\nlet b = 2")
        let secondLet = (storage.string as NSString).range(of: "let b").location
        XCTAssertEqual(storage.attribute(.foregroundColor, at: secondLet,
                                         effectiveRange: nil) as? NSColor, .systemPink)
        XCTAssertNotNil(storage.attribute(.paragraphStyle, at: secondLet, effectiveRange: nil))
    }

    func testDeletingNewlineRestylesJoinedLogicalLine() {
        let storage = NSTextStorage(attributedString:
            ConflictOutputEditorView.highlightedText("let a = 1\nlet b = 2", filePath: "code.swift", font: font)
        )
        let newline = (storage.string as NSString).range(of: "\n")
        storage.replaceCharacters(in: newline, with: "")
        ConflictOutputEditorView.highlightEditedLines(
            in: storage, editedRange: NSRange(location: newline.location, length: 0),
            filePath: "code.swift", font: font
        )
        let secondLet = (storage.string as NSString).range(of: "let b").location
        XCTAssertEqual(storage.string, "let a = 1let b = 2")
        // Joining the lines removes the word boundary before the second `let`.
        // It must lose the stale keyword color inherited from the old line.
        XCTAssertEqual(storage.attribute(.foregroundColor, at: secondLet, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemPink)
        XCTAssertNotNil(storage.attribute(.paragraphStyle, at: secondLet, effectiveRange: nil))
    }

    func testEditingLastLineWithoutTerminalNewlineKeepsSyntaxHighlight() {
        let storage = NSTextStorage(attributedString:
            ConflictOutputEditorView.highlightedText("first\nlet a = 1", filePath: "code.swift", font: font)
        )
        let last = (storage.string as NSString).range(of: "let a")
        storage.replaceCharacters(in: last, with: "let b")
        ConflictOutputEditorView.highlightEditedLines(
            in: storage, editedRange: NSRange(location: last.location, length: 5),
            filePath: "code.swift", font: font
        )
        XCTAssertEqual(storage.attribute(.foregroundColor, at: last.location, effectiveRange: nil) as? NSColor, .systemPink)
        XCTAssertEqual(storage.string, "first\nlet b = 1")
    }

    func testInlineCommentAfterEmojiUsesUTF16Offset() {
        let line = "🙂 let value = 1 // comment"
        let highlighted = CodeSyntaxHighlighter.highlight(line, language: .swift, font: font)
        let comment = (line as NSString).range(of: "// comment")

        XCTAssertEqual(highlighted.attribute(.foregroundColor, at: comment.location,
                                             effectiveRange: nil) as? NSColor, .systemGreen)
        XCTAssertEqual(highlighted.attribute(.foregroundColor, at: comment.location - 1,
                                             effectiveRange: nil) as? NSColor, .labelColor)
    }
}
