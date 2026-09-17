import Foundation
import CryptoKit

// MARK: - OperationHistoryStoring

/// per-Repo 操作历史的持久化抽象。可注入以便测试与失败注入。
///
/// - `load()`：从 `History_Store` 读取已持久化历史；文件缺失时返回空数组（2.4），
///   数据损坏/无法解析时抛出可识别的 decode 错误（2.5）。
/// - `save(_:)`：将历史写入 `History_Store`；采用「临时文件 + 原子替换」减少半写风险（2.1）。
protocol OperationHistoryStoring: Sendable {
    func load() throws -> [OperationLogEntry]
    func save(_ entries: [OperationLogEntry]) throws
}

// MARK: - OperationHistoryStoreError

/// `OperationHistoryStore` 抛出的可识别错误。
///
/// `decodeFailed` 供 service 层捕获后转为空历史 + 记诊断日志（2.5）。
enum OperationHistoryStoreError: Error {
    /// 已持久化数据损坏或无法解析（携带底层解码错误）。
    case decodeFailed(underlying: Error)
    /// 无法定位/创建 Application Support 目录。
    case storeLocationUnavailable(underlying: Error)
}

// MARK: - OperationHistoryStore

/// per-Repo JSON 文件的持久化实现。
///
/// 位置：`Application Support/GitN/OperationHistory/<repoKey>.json`。
/// 磁盘格式为带 `schemaVersion` 的 JSON 包裹，`entries` 为 `[OperationLogEntry]`，
/// 其中 `Data` 字段由 `Codable`/`JSONEncoder` 默认以 base64 编码（round-trip 逐字节一致）。
struct OperationHistoryStore: OperationHistoryStoring {
    /// per-repo JSON 文件绝对路径。
    let fileURL: URL

    /// 当前磁盘 schema 版本，便于后续演进。
    static let schemaVersion = 1

    // MARK: Persisted wrapper

    /// 磁盘 JSON 顶层包裹：`{ "schemaVersion": 1, "entries": [...] }`。
    private struct Payload: Codable {
        var schemaVersion: Int
        var entries: [OperationLogEntry]
    }

    // MARK: Init

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 由 `repoPath` 派生 store 文件位置，并按需创建承载目录。
    ///
    /// - 目录：`Application Support/GitN/OperationHistory/`（不存在则创建）。
    /// - 文件名：`<repoKey>.json`，`repoKey` 为标准化路径的稳定 SHA-256 哈希。
    init(repoPath: String, fileManager: FileManager = .default) throws {
        let directory = try Self.historyDirectory(fileManager: fileManager)
        let key = Self.repoKey(for: repoPath)
        self.fileURL = directory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    // MARK: OperationHistoryStoring

    func load() throws -> [OperationLogEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 缺失文件（或不可读）→ 视为空历史，不报错（2.4）。
            if Self.isFileNotFound(error) {
                return []
            }
            return []
        }

        // 空文件同样视为空历史，不抛错。
        guard !data.isEmpty else { return [] }

        do {
            let payload = try Self.decoder.decode(Payload.self, from: data)
            return payload.entries
        } catch {
            // 损坏/无法解析 → 抛出可识别的 decode 错误（由 service 转空历史 + 诊断）（2.5）。
            throw OperationHistoryStoreError.decodeFailed(underlying: error)
        }
    }

    func save(_ entries: [OperationLogEntry]) throws {
        let payload = Payload(schemaVersion: Self.schemaVersion, entries: entries)
        let data = try Self.encoder.encode(payload)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 临时文件 + 原子替换：先写入同目录下的临时文件，再原子替换目标文件，
        // 降低进程中断导致的半写风险（2.1）。
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: repoKey / location

    /// 由 `repoPath` 生成稳定 key：标准化路径后取 SHA-256 十六进制。
    ///
    /// 标准化流程：`standardizedFileURL.resolvingSymlinksInPath().path`，避免符号链接、
    /// `..`、尾随斜杠等造成同一仓库产生不同 key，并规避路径中的非法文件名字符。
    static func repoKey(for repoPath: String) -> String {
        let normalized = URL(fileURLWithPath: repoPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 定位并按需创建操作历史承载目录：`Application Support/GitN/OperationHistory/`。
    static func historyDirectory(fileManager: FileManager = .default) throws -> URL {
        let base: URL
        do {
            base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw OperationHistoryStoreError.storeLocationUnavailable(underlying: error)
        }

        let directory = base
            .appendingPathComponent("GitN", isDirectory: true)
            .appendingPathComponent("OperationHistory", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw OperationHistoryStoreError.storeLocationUnavailable(underlying: error)
        }

        return directory
    }

    // MARK: Coders

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // `Data` 字段默认以 base64 编码（Foundation 默认策略）。
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Helpers

    private static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOENT) {
            return true
        }
        return false
    }
}
