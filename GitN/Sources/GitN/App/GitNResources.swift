import Foundation

enum GitNResources {
    private static let fileManager = FileManager.default
    private static let sourceRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let featuresSourceURL = sourceRootURL.appendingPathComponent("FEATURES.md")
    private static let monacoSourceDirectoryURL = sourceRootURL
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Monaco", isDirectory: true)

    private static var appResourceBundles: [Bundle] {
        guard let resourceURL = Bundle.main.resourceURL,
              let urls = try? fileManager.contentsOfDirectory(
                  at: resourceURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "bundle" }
            .compactMap(Bundle.init(url:))
    }

    static var featuresURL: URL? {
        if let directURL = firstExistingFileURL([
            Bundle.main.resourceURL?.appendingPathComponent("FEATURES.md"),
        ]) {
            return directURL
        }

        for bundle in appResourceBundles {
            if let url = bundle.url(forResource: "FEATURES", withExtension: "md") {
                return url
            }
        }

        return firstExistingFileURL([featuresSourceURL])
    }

    static var monacoDirectoryURL: URL? {
        if let directURL = firstExistingDirectoryURL([
            Bundle.main.resourceURL?.appendingPathComponent("Monaco", isDirectory: true),
        ]) {
            return directURL
        }

        for bundle in appResourceBundles {
            if let url = firstExistingDirectoryURL([
                bundle.resourceURL?.appendingPathComponent("Monaco", isDirectory: true),
            ]) {
                return url
            }
        }

        return firstExistingDirectoryURL([monacoSourceDirectoryURL])
    }

    static var monacoIndexURL: URL? {
        if let directURL = firstExistingFileURL([
            Bundle.main.resourceURL?
                .appendingPathComponent("Monaco", isDirectory: true)
                .appendingPathComponent("index.html"),
        ]) {
            return directURL
        }

        for bundle in appResourceBundles {
            if let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Monaco") {
                return url
            }
        }

        return firstExistingFileURL([
            monacoSourceDirectoryURL.appendingPathComponent("index.html"),
        ])
    }

    private static func firstExistingFileURL(_ candidates: [URL?]) -> URL? {
        candidates.compactMap { $0 }.first { candidate in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                return false
            }
            return !isDirectory.boolValue
        }
    }

    private static func firstExistingDirectoryURL(_ candidates: [URL?]) -> URL? {
        candidates.compactMap { $0 }.first { candidate in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                return false
            }
            return isDirectory.boolValue
        }
    }
}
