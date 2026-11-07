import CryptoKit
import Darwin
import Foundation

enum SSHHostKeyService {
    static func mayOfferTrust(error: String) -> Bool {
        let message = error.lowercased()
        guard !message.contains("has changed"), !message.contains("offending"),
              !message.contains("revoked"), !message.contains("identification has changed") else { return false }
        return message.contains("host key verification failed") || message.contains("host key")
    }

    struct Endpoint: Equatable {
        let host: String
        let port: UInt16
        var knownHostsName: String { port == 22 ? host : "[\(host)]:\(port)" }

        init(_ value: String) throws {
            var host = value
            var port: UInt16 = 22
            if value.hasPrefix("["), let end = value.firstIndex(of: "]") {
                host = String(value[value.index(after: value.startIndex)..<end])
                let suffix = String(value[value.index(after: end)...])
                if !suffix.isEmpty {
                    guard suffix.hasPrefix(":"), let parsed = UInt16(suffix.dropFirst()), parsed > 0 else {
                        throw Failure.invalidHost
                    }
                    port = parsed
                }
            }
            var ipv6 = in6_addr()
            let isIPv6 = host.withCString { inet_pton(AF_INET6, $0, &ipv6) } == 1
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            let isDNS = !host.isEmpty && host.utf8.count <= 253 && labels.allSatisfy { label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
            }
            guard isIPv6 || isDNS else { throw Failure.invalidHost }
            self.host = host
            self.port = port
        }
    }

    struct Key: Equatable {
        let algorithm: String
        let fingerprint: String
        fileprivate let line: String
    }

    struct Candidate: Equatable {
        let endpoint: Endpoint
        let keys: [Key]
        fileprivate init(endpoint: Endpoint, keys: [Key]) { self.endpoint = endpoint; self.keys = keys }
    }

    enum Failure: LocalizedError {
        case invalidHost, invalidKeys, unsafeFile, scanFailed, existingTrust
        var errorDescription: String? {
            switch self {
            case .invalidHost: "Invalid SSH host or port."
            case .invalidKeys: "The SSH scan returned invalid or unexpected keys."
            case .unsafeFile: "The SSH known_hosts path must be a regular file owned by the current user, without symlinks."
            case .scanFailed: "Unable to scan SSH host keys. Check the host, port and network."
            case .existingTrust: "This host already has a known_hosts entry. Verify existing trust manually; GitN will not replace or add keys for it."
            }
        }
    }

    static func scan(host: String) async throws -> Candidate {
        let endpoint = try Endpoint(host)
        let output = try await BoundedProcessRunner.run(executable: "/usr/bin/ssh-keyscan",
            arguments: ["-T", "5", "-p", String(endpoint.port), "-t", "ed25519,ecdsa,rsa", endpoint.host], timeout: 20)
        guard output.status == 0, let text = String(data: output.stdout, encoding: .utf8) else { throw Failure.scanFailed }
        return try parse(text, endpoint: endpoint)
    }

    static func parse(_ text: String, endpoint: Endpoint) throws -> Candidate {
        guard text.utf8.count <= 262_144 else { throw Failure.invalidKeys }
        var keys: [Key] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, fields[0] == endpoint.knownHostsName,
                  let blob = Data(base64Encoded: String(fields[2])), blob.count <= 16_384,
                  validWireKey(blob, algorithm: String(fields[1])) else { throw Failure.invalidKeys }
            let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
            let key = Key(algorithm: String(fields[1]), fingerprint: "SHA256:\(digest)", line: fields.joined(separator: " "))
            if !keys.contains(key) { keys.append(key) }
        }
        guard !keys.isEmpty else { throw Failure.invalidKeys }
        return Candidate(endpoint: endpoint, keys: keys)
    }

    private static func validWireKey(_ data: Data, algorithm: String) -> Bool {
        var offset = 0
        func field() -> Data? {
            guard data.count - offset >= 4 else { return nil }
            let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard length <= data.count - offset else { return nil }
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }
        guard let type = field(), String(data: type, encoding: .utf8) == algorithm else { return false }
        switch algorithm {
        case "ssh-ed25519":
            guard field()?.count == 32 else { return false }
        case "ssh-rsa":
            guard let exponent = field(), !exponent.isEmpty, exponent.count <= 8,
                  let modulus = field(), modulus.count >= 256 else { return false }
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            let curve = String(algorithm.dropFirst("ecdsa-sha2-".count))
            let pointLength = ["nistp256": 65, "nistp384": 97, "nistp521": 133][curve]!
            guard let encodedCurve = field(), String(data: encodedCurve, encoding: .utf8) == curve,
                  let point = field(), point.count == pointLength, point.first == 4 else { return false }
        default: return false
        }
        return offset == data.count
    }

    /// Persists this immutable, reviewed batch. Never scans again here.
    static func trust(_ candidate: Candidate, directory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw Failure.unsafeFile }
        defer { close(dirFD) }
        var dirInfo = stat()
        guard fstat(dirFD, &dirInfo) == 0, dirInfo.st_uid == geteuid(), dirInfo.st_mode & 0o022 == 0 else { throw Failure.unsafeFile }
        let fd = openat(dirFD, "known_hosts", O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw Failure.unsafeFile }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
              flock(fd, LOCK_EX) == 0, fchmod(fd, 0o600) == 0 else { throw Failure.unsafeFile }
        defer { flock(fd, LOCK_UN) }
        guard info.st_size <= 4_194_304 else { throw Failure.unsafeFile }
        var existing = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw Failure.unsafeFile }
            if count == 0 { break }
            existing.append(contentsOf: buffer.prefix(count))
            guard existing.count <= 4_194_304 else { throw Failure.unsafeFile }
        }
        for line in String(decoding: existing, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let first = fields.first, !first.hasPrefix("#") else { continue }
            let names = first.hasPrefix("@") ? fields.dropFirst().first : first
            if let names, matchesHost(String(names), host: candidate.endpoint.knownHostsName) {
                throw Failure.existingTrust
            }
        }
        let data = Data(("\n" + candidate.keys.map(\.line).joined(separator: "\n") + "\n").utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
    }

    static func matchesHost(_ names: String, host: String) -> Bool {
        if names.hasPrefix("|1|") {
            let parts = names.split(separator: "|", omittingEmptySubsequences: true)
            guard parts.count == 3, let salt = Data(base64Encoded: String(parts[1])),
                  let expected = Data(base64Encoded: String(parts[2])) else { return false }
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(host.utf8), using: SymmetricKey(data: salt))) == expected
        }
        var matched = false
        for raw in names.split(separator: ",") {
            let negated = raw.hasPrefix("!")
            let pattern = negated ? String(raw.dropFirst()) : String(raw)
            if pattern.lowercased() == host.lowercased() || fnmatch(pattern.lowercased(), host.lowercased(), 0) == 0 {
                if negated { return false }
                matched = true
            }
        }
        return matched
    }
}
