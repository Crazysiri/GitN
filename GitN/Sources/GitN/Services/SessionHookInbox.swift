import Foundation

struct SessionHookInbox: Sendable {
    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GitN/Workbench/inbox", isDirectory: true)
    let url: URL
    init(url: URL = Self.defaultURL) { self.url = url }

    struct Item { let url: URL; let event: SessionHookEnvelope }

    func pending() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200)
            .compactMap { file in
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 65536,
                      let event = try? JSONDecoder().decode(SessionHookEnvelope.self, from: Data(contentsOf: file)),
                      (try? event.observation()) != nil else {
                    try archive(file, directory: "rejected")
                    return nil
                }
                return Item(url: file, event: event)
            }
    }

    func acknowledge(_ item: Item) throws { try archive(item.url, directory: "processed") }

    private func archive(_ file: URL, directory: String) throws {
        let archive = url.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let destination = archive.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.moveItem(at: file, to: destination)
    }
}
