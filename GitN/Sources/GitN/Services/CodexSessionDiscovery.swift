import Foundation
import Darwin

struct CodexSessionDiscovery: Sendable {
    let executable: URL
    let namespace: String
    var timeout: TimeInterval = 20

    static func installedExecutable() -> URL? {
        let directories = (GitCLI.enrichedEnvironment()["PATH"] ?? "").split(separator: ":")
        return directories.map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func discover() async throws -> [SessionObservation] {
        let control = SessionDiscoveryProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try self.run(control: control)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { control.cancel() }
    }

    private func run(control: SessionDiscoveryProcess) throws -> [SessionObservation] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.environment = GitCLI.enrichedEnvironment()
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // A server exiting between requests must become an error, not SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw GitError.operationFailed("Unable to configure the Codex metadata pipe.")
        }
        // Server diagnostics can contain local metadata. Do not retain or log them.
        process.standardError = FileHandle.nullDevice
        try process.run()
        control.started(process)
        defer {
            try? input.fileHandleForWriting.close()
            control.cancel()
            try? output.fileHandleForReading.close()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { control.cancel() }
        var buffer = Data()
        var bytesRead = 0
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(id: Int) throws -> [String: Any] {
            while true {
                if let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    guard message["id"] as? Int == id else { continue }
                    if message["error"] != nil { throw GitError.operationFailed("Codex rejected the read-only session request. Check CLI version and configuration.") }
                    guard let result = message["result"] as? [String: Any] else {
                        throw GitError.operationFailed("Unexpected Codex metadata response.")
                    }
                    return result
                }
                // FileHandle.read(upToCount:) may fill the requested count on pipes.
                // Protocol replies are often shorter and must be processed immediately.
                var storage = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &storage, storage.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw GitError.operationFailed("Codex session discovery ended or timed out. No conversation was started.")
                }
                let chunk = Data(storage.prefix(count))
                bytesRead += chunk.count
                guard bytesRead <= 16_000_000, buffer.count <= 2_000_000 else {
                    throw GitError.operationFailed("Codex metadata exceeds the discovery limit.")
                }
                buffer.append(chunk)
            }
        }
        try send(["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": [
            "clientInfo": ["name": "gitn", "title": "GitN", "version": "0.1"]]])
        _ = try response(id: 0)
        try send(["jsonrpc": "2.0", "method": "initialized"])
        var observations: [SessionObservation] = []
        var cursor: String?
        var seenCursors = Set<String>()
        for page in 1...20 {
            var params: [String: Any] = ["limit": 50, "sortKey": "updated_at", "sourceKinds": ["cli", "vscode", "appServer"]]
            if let cursor { params["cursor"] = cursor }
            try send(["jsonrpc": "2.0", "id": page, "method": "thread/list", "params": params])
            let result = try response(id: page)
            observations += try Self.parsePage(result, namespace: namespace)
            cursor = result["nextCursor"] as? String
            guard let next = cursor else { return observations }
            guard seenCursors.insert(next).inserted else { throw GitError.operationFailed("Codex returned a repeated pagination cursor.") }
        }
        throw GitError.operationFailed("More than 1,000 Codex sessions found. Discovery stopped without importing a partial list.")
    }

    static func parsePage(_ result: [String: Any], namespace: String) throws -> [SessionObservation] {
        guard let threads = result["data"] as? [[String: Any]] else { throw GitError.operationFailed("Invalid Codex thread list.") }
        return try threads.map { thread in
            guard let id = thread["id"] as? String, !id.isEmpty else { throw GitError.operationFailed("Codex thread ID missing.") }
            let updated = (thread["updatedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
            return SessionObservation(agent: .codex, namespace: namespace, externalID: id,
                title: thread["name"] as? String, cwd: thread["cwd"] as? String, observedAt: updated)
        }
    }
}

private final class SessionDiscoveryProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func started(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        if cancelled { if process.isRunning { process.terminate() } }
        else { self.process = process }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        self.process = nil
    }
}
