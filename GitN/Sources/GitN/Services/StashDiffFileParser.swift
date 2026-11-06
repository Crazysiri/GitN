import Foundation

/// Parses Git's NUL-delimited path protocol without applying core.quotepath escaping.
enum StashDiffFileParser {
    static func parse(status: Data, numstat: Data, untracked: Data?) throws -> [DiffFile] {
        let statusFields = try fields(status)
        let statFields = try fields(numstat)
        let untrackedFields = try fields(untracked ?? Data())
        let stats = try parseStats(statFields)
        var files: [DiffFile] = []
        var seen = Set<String>()
        var index = 0

        while index < statusFields.count {
            let code = try string(statusFields[index])
            index += 1
            guard let marker = code.first, "ACDMRTUXB".contains(marker), index < statusFields.count else {
                throw GitError.operationFailed("Malformed stash name-status output")
            }
            let firstPath = try string(statusFields[index])
            index += 1
            let oldPath: String?
            let path: String
            if marker == "R" || marker == "C" {
                guard index < statusFields.count else {
                    throw GitError.operationFailed("Malformed stash rename output")
                }
                oldPath = firstPath
                path = try string(statusFields[index])
                index += 1
            } else {
                oldPath = nil
                path = firstPath
            }
            guard !path.isEmpty else { throw GitError.operationFailed("Empty stash path") }
            let changeKind: DiffChangeKind
            switch marker {
            case "A": changeKind = .added
            case "D": changeKind = .deleted
            case "R": changeKind = .renamed
            case "C": changeKind = .copied
            case "M", "T": changeKind = .modified
            default: changeKind = .unknown
            }
            let count = stats[path] ?? (0, 0)
            files.append(DiffFile(
                additions: count.0, deletions: count.1, path: path,
                oldPath: oldPath, changeKind: changeKind
            ))
            seen.insert(path)
        }

        for field in untrackedFields {
            let path = try string(field)
            guard !path.isEmpty else { throw GitError.operationFailed("Empty untracked stash path") }
            if seen.insert(path).inserted {
                files.append(DiffFile(additions: 1, deletions: 0, path: path, changeKind: .untracked))
            }
        }
        return files
    }

    private static func parseStats(_ fields: [Data]) throws -> [String: (Int, Int)] {
        var stats: [String: (Int, Int)] = [:]
        var index = 0
        while index < fields.count {
            let header = try string(fields[index])
            index += 1
            let parts = header.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { throw GitError.operationFailed("Malformed stash numstat output") }
            let path: String
            if parts[2].isEmpty {
                guard index + 1 < fields.count else {
                    throw GitError.operationFailed("Malformed stash rename numstat")
                }
                _ = try string(fields[index]) // old path
                path = try string(fields[index + 1])
                index += 2
            } else {
                path = String(parts[2])
            }
            guard !path.isEmpty else { throw GitError.operationFailed("Empty stash numstat path") }
            stats[path] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        return stats
    }

    private static func fields(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else { return [] }
        guard data.last == 0 else { throw GitError.operationFailed("Unterminated stash path output") }
        let trimmed = data[data.startIndex..<data.index(before: data.endIndex)]
        let separator: UInt8 = 0
        let chunks: [Data.SubSequence] = trimmed.split(separator: separator, omittingEmptySubsequences: false)
        return chunks.map { Data($0) }
    }

    private static func string(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw GitError.operationFailed("Non-UTF-8 stash path output")
        }
        return value
    }
}
