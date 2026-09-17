import XCTest
@testable import GitN

/// `OperationHistoryStore` 的边界测试：缺失文件与数据损坏。
///
/// 对齐设计文档中：
/// - EDGE_CASE 2.4：文件缺失时 `load` 返回空历史且不报错。
/// - EDGE_CASE 2.5：注入随机非法字节，断言 `load` 抛出可识别的 `decodeFailed`
///   （供 service 层捕获后转空历史 + 记诊断日志）。
///
/// 使用独立测试文件以避免与 task 2.2 并发创建的
/// `OperationHistoryStoreTests.swift` 产生写入冲突。
final class OperationHistoryStoreEdgeTests: XCTestCase {
    /// 本用例创建的临时文件/目录，在 tearDown 中清理。
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for url in temporaryURLs {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        temporaryURLs.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// 生成一个（尚不存在的）临时目录内文件 URL，并登记以便清理。
    private func makeTemporaryFileURL(name: String = UUID().uuidString + ".json") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OperationHistoryStoreEdgeTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        // 登记目录以便递归清理临时文件。
        temporaryURLs.append(directory)
        return fileURL
    }

    // MARK: - EDGE_CASE 2.4

    /// 文件缺失时，`load()` 应返回空历史且不抛错。
    func testLoadReturnsEmptyHistoryWhenFileMissing() throws {
        let missingURL = makeTemporaryFileURL()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingURL.path),
            "前置条件：目标文件不应存在"
        )

        let store = OperationHistoryStore(fileURL: missingURL)

        let entries = try store.load()

        XCTAssertTrue(entries.isEmpty, "文件缺失时 load() 应返回空历史")
    }

    /// 承载目录整个缺失时（父目录都不存在），同样返回空历史且不抛错。
    func testLoadReturnsEmptyHistoryWhenDirectoryMissing() throws {
        let missingURL = makeTemporaryFileURL()
        // 目录尚未创建。
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingURL.deletingLastPathComponent().path),
            "前置条件：承载目录不应存在"
        )

        let store = OperationHistoryStore(fileURL: missingURL)

        XCTAssertEqual(try store.load(), [], "承载目录缺失时 load() 应返回空历史")
    }

    // MARK: - EDGE_CASE 2.5

    /// 写入随机非法字节后，`load()` 应抛出可识别的 `OperationHistoryStoreError.decodeFailed`。
    func testLoadThrowsDecodeFailedForRandomInvalidBytes() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 注入随机非法字节（非合法 JSON、包含非 UTF-8 序列）。
        var garbage = Data()
        for _ in 0..<256 {
            garbage.append(UInt8.random(in: 0...255))
        }
        // 追加一段明确的非 UTF-8 序列，确保不是恰好合法的 JSON。
        garbage.append(contentsOf: [0xFF, 0xFE, 0xFD, 0x00, 0x7B, 0xC0, 0x80])
        try garbage.write(to: fileURL, options: .atomic)

        let store = OperationHistoryStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load(), "损坏数据时 load() 应抛错") { error in
            guard let storeError = error as? OperationHistoryStoreError else {
                return XCTFail("期望 OperationHistoryStoreError，实际为 \(error)")
            }
            switch storeError {
            case .decodeFailed:
                break // 期望的可识别 decode 错误。
            case .storeLocationUnavailable:
                XCTFail("期望 .decodeFailed，实际为 .storeLocationUnavailable")
            }
        }
    }

    /// 结构上是合法 UTF-8 文本但不是有效 payload JSON 时，同样抛出 `.decodeFailed`。
    func testLoadThrowsDecodeFailedForMalformedJSONText() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let malformed = Data("{ this is not valid json ]".utf8)
        try malformed.write(to: fileURL, options: .atomic)

        let store = OperationHistoryStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case OperationHistoryStoreError.decodeFailed = error else {
                return XCTFail("期望 OperationHistoryStoreError.decodeFailed，实际为 \(error)")
            }
        }
    }
}
