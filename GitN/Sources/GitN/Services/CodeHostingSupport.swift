import Foundation

enum CodeHostingSupportError: Error {
    case invalidURL(String)
    case invalidResponse
    case networkError(String)
    case apiError(Int, String)
    case gitFailed(String)
}

enum CodeHostingRemote {
    static func parseRepositoryPath(from remoteURL: String) -> String? {
        var path: String

        if remoteURL.contains("@"), remoteURL.contains(":") {
            guard let colonIndex = remoteURL.firstIndex(of: ":") else { return nil }
            path = String(remoteURL[remoteURL.index(after: colonIndex)...])
        } else if remoteURL.hasPrefix("http://") || remoteURL.hasPrefix("https://") {
            guard let url = URL(string: remoteURL) else { return nil }
            path = url.path
            if path.hasPrefix("/") {
                path = String(path.dropFirst())
            }
        } else {
            return nil
        }

        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }

        return path.isEmpty ? nil : path
    }

    static func parseHost(from remoteURL: String) -> String? {
        let normalizedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: normalizedURL), let host = url.host?.lowercased(), !host.isEmpty {
            return host
        }

        if normalizedURL.contains("@"), normalizedURL.contains(":") {
            guard
                let atIndex = normalizedURL.firstIndex(of: "@"),
                let colonIndex = normalizedURL[atIndex...].firstIndex(of: ":"),
                atIndex < colonIndex
            else {
                return nil
            }

            let host = normalizedURL[normalizedURL.index(after: atIndex)..<colonIndex]
                .lowercased()
            return host.isEmpty ? nil : String(host)
        }

        return nil
    }
}

struct CodeHostingGitRunner {
    let repoPath: String

    func run(_ args: [String]) async throws {
        _ = try await execute(args: args, captureOutput: false)
    }

    func runOutput(_ args: [String]) async throws -> String {
        let output = try await execute(args: args, captureOutput: true)
        return output ?? ""
    }

    private func execute(args: [String], captureOutput: Bool) async throws -> String? {
        let path = repoPath
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: path)
                process.environment = Self.enrichedEnvironment()

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let message = String(data: errorData, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                        continuation.resume(
                            throwing: CodeHostingSupportError.gitFailed(
                                message.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        return
                    }

                    guard captureOutput else {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: String(data: outputData, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            NSHomeDirectory() + "/.local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }
        return env
    }
}

enum CodeHostingAPIClient {
    static func request(
        url urlString: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw CodeHostingSupportError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodeHostingSupportError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw CodeHostingSupportError.apiError(httpResponse.statusCode, responseBody)
        }
        return data
    }
}
