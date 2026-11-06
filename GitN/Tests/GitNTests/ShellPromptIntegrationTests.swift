import XCTest
@testable import GitN

final class ShellPromptIntegrationTests: XCTestCase {
    func testShellDetection() {
        XCTAssertEqual(ShellPromptIntegration.shell(forExecutable: "/bin/zsh"), .zsh)
        XCTAssertEqual(ShellPromptIntegration.shell(forExecutable: "/usr/local/bin/bash"), .bash)
        XCTAssertEqual(ShellPromptIntegration.shell(forExecutable: "/bin/sh"), .bash)
        XCTAssertNil(ShellPromptIntegration.shell(forExecutable: "/usr/bin/fish"))
    }

    func testZshWrapperHasReentrancyGuard() {
        let script = ShellPromptIntegration.zdotdirZshrc()
        XCTAssertTrue(script.contains("GITN_PROMPT_WRAPPED"), "must guard against double-wrapping")
        XCTAssertTrue(script.contains("add-zsh-hook precmd"), "re-applies via precmd so it survives PS1 rebuilds")
        XCTAssertTrue(script.contains("GITN_USER_ZDOTDIR"), "restores the user's ZDOTDIR")
        XCTAssertTrue(script.contains("source"), "sources the user's own init files")
        // Marker appended to the END of PS1, and prior copies stripped first so
        // it is never duplicated.
        XCTAssertTrue(script.contains("$__gitn_prompt_mark"))
    }

    func testZshWrapperEmitsTheMarker() {
        // The marker's numeric code (7000) must be present in the emitted sequence.
        let script = ShellPromptIntegration.zdotdirZshrc()
        XCTAssertTrue(script.contains("7000~"))
    }

    func testBashWrapperChainsPromptCommandWithoutClobbering() {
        let script = ShellPromptIntegration.bashRCFile()
        XCTAssertTrue(script.contains("GITN_PROMPT_WRAPPED"))
        // Must detect an already-installed hook and chain onto an existing
        // PROMPT_COMMAND rather than clobbering it.
        XCTAssertTrue(script.contains("*__gitn_apply_prompt*"))
        XCTAssertTrue(script.contains("$PROMPT_COMMAND; __gitn_apply_prompt"))
        // The marker is appended to the END of PS1 (input start column).
        XCTAssertTrue(script.contains("PS1=\"$PS1$__gitn_prompt_mark\""))
        XCTAssertTrue(script.contains("7000~"))
    }

    func testMarkerCSIBytes() {
        // ESC [ 7000 ~
        XCTAssertEqual(ShellPromptIntegration.promptMarkerCSI, "\u{001B}[7000~")
    }
}
