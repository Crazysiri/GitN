import XCTest
@testable import GitN

final class TerminalSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "TerminalSettingsTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsMatchSpec() {
        let s = TerminalSettings.default
        XCTAssertEqual(s.fontSize, 12)
        XCTAssertEqual(s.cursorStyle, "bar")
        XCTAssertEqual(s.scrollback, 5000)
        XCTAssertTrue(s.suggestionsEnabled)
        XCTAssertEqual(s.tabMode, "NAVIGATION")
    }

    func testRoundTripPersistence() {
        let defaults = makeDefaults()
        var s = TerminalSettings.default
        s.fontSize = 16
        s.cursorStyle = "block"
        s.scrollback = 20000
        s.suggestionsEnabled = false
        s.tabMode = "ENTER"
        s.save(to: defaults)

        let loaded = TerminalSettings.load(from: defaults)
        XCTAssertEqual(loaded, s)
    }

    func testFontSizeClamping() {
        XCTAssertEqual(TerminalSettings.clampFontSize(2), TerminalSettings.fontSizeRange.lowerBound)
        XCTAssertEqual(TerminalSettings.clampFontSize(999), TerminalSettings.fontSizeRange.upperBound)
        XCTAssertEqual(TerminalSettings.clampFontSize(14), 14)
    }

    func testLoadRejectsInvalidCursorStyle() {
        let defaults = makeDefaults()
        defaults.set("triangle", forKey: "GitN.terminal.cursorStyle")
        let loaded = TerminalSettings.load(from: defaults)
        XCTAssertEqual(loaded.cursorStyle, "bar", "invalid style falls back to default")
    }

    func testStartOptionsDictionaryShape() {
        let dict = TerminalSettings.default.startOptionsDictionary
        XCTAssertEqual(dict["fontSize"] as? Int, 12)
        XCTAssertEqual(dict["cursorStyle"] as? String, "bar")
        XCTAssertEqual(dict["tabMode"] as? String, "NAVIGATION")
        XCTAssertEqual(dict["suggestionsEnabled"] as? Bool, true)
    }
}
