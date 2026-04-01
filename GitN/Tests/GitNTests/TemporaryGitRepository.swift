import Foundation

final class TemporaryGitRepository {
    struct CommandError: LocalizedError {
        let arguments: [String]
        let output: String

        var errorDescription: String? {
            let command = (["git"] + arguments).joined(separator: " ")
            return "\(command)\n\(output)"
        }
    }

    let url: URL

    var path: String { url.path }

    init() throws {
        let root = FileManager.default.temporaryDirectory
        url = root.appendingPathComponent("GitNTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        try run(["init", "-b", "main"])
        try run(["config", "user.name", "GitN Tests"])
        try run(["config", "user.email", "gitn-tests@example.com"])
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writeFile(_ relativePath: String, contents: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        let parentURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func appendFile(_ relativePath: String, contents: String) throws {
        let existing = (try? readFile(relativePath)) ?? ""
        try writeFile(relativePath, contents: existing + contents)
    }

    func readFile(_ relativePath: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @discardableResult
    func run(_ arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData + errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw CommandError(arguments: arguments, output: output)
        }

        return output
    }

    @discardableResult
    func commitAll(message: String, environment: [String: String] = [:]) throws -> String {
        try run(["add", "."])
        try run(["commit", "-m", message], environment: environment)
        return try headHash()
    }

    func headHash() throws -> String {
        try run(["rev-parse", "HEAD"])
    }
}
