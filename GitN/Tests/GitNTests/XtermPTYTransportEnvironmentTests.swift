import XCTest
@testable import GitN

final class XtermPTYTransportEnvironmentTests: XCTestCase {
    private func dict(from env: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in env {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<eq])
            let value = String(entry[entry.index(after: eq)...])
            result[key] = value
        }
        return result
    }

    func testForcesTerminalIdentity() {
        let env = XtermPTYTransport.buildEnvironment(base: ["TERM": "dumb", "PATH": "/usr/bin"])
        let parsed = dict(from: env)
        XCTAssertEqual(parsed["TERM"], "xterm-256color")
        XCTAssertEqual(parsed["TERM_PROGRAM"], "GitN")
    }

    func testPreservesUserEnvironment() {
        let base = [
            "PATH": "/opt/homebrew/bin:/usr/bin",
            "HOME": "/Users/example",
            "SSH_AUTH_SOCK": "/tmp/ssh.sock",
            "HTTP_PROXY": "http://proxy:8080",
        ]
        let parsed = dict(from: XtermPTYTransport.buildEnvironment(base: base))
        XCTAssertEqual(parsed["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(parsed["HOME"], "/Users/example")
        XCTAssertEqual(parsed["SSH_AUTH_SOCK"], "/tmp/ssh.sock")
        XCTAssertEqual(parsed["HTTP_PROXY"], "http://proxy:8080")
    }

    func testDefaultsLangWhenMissingButKeepsExisting() {
        let without = dict(from: XtermPTYTransport.buildEnvironment(base: [:]))
        XCTAssertEqual(without["LANG"], "en_US.UTF-8")

        let withExisting = dict(from: XtermPTYTransport.buildEnvironment(base: ["LANG": "zh_CN.UTF-8"]))
        XCTAssertEqual(withExisting["LANG"], "zh_CN.UTF-8")
    }

    func testNoDuplicateKeys() {
        let env = XtermPTYTransport.buildEnvironment(base: ["TERM": "dumb", "LANG": "C"])
        let keys = env.compactMap { $0.split(separator: "=", maxSplits: 1).first.map(String.init) }
        XCTAssertEqual(keys.count, Set(keys).count, "environment must not contain duplicate keys")
    }
}
