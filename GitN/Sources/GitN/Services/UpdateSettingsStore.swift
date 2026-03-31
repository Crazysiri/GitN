import Foundation

struct UpdateConfiguration: Equatable {
    let defaultFeedURLString: String?
    let publicEDKey: String?

    var isPublicKeyConfigured: Bool {
        guard let publicEDKey else { return false }
        return !publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var defaultFeedURL: URL? {
        UpdateFeedResolver.normalizedFeedURL(from: defaultFeedURLString)
    }
}

final class UpdateSettingsStore {
    static let shared = UpdateSettingsStore()

    static let customFeedURLKey = "GitN.update.customFeedURL"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var customFeedURLString: String {
        defaults.string(forKey: Self.customFeedURLKey) ?? ""
    }

    var customFeedURL: URL? {
        UpdateFeedResolver.normalizedFeedURL(from: customFeedURLString)
    }

    @discardableResult
    func saveCustomFeedURLString(_ candidate: String) -> String {
        let normalized = UpdateFeedResolver.normalizedFeedURLString(from: candidate) ?? ""
        if normalized.isEmpty {
            defaults.removeObject(forKey: Self.customFeedURLKey)
        } else {
            defaults.set(normalized, forKey: Self.customFeedURLKey)
        }
        return normalized
    }

    func clearCustomFeedURL() {
        defaults.removeObject(forKey: Self.customFeedURLKey)
    }
}

struct UpdateFeedResolver {
    private let settingsStore: UpdateSettingsStore
    private let defaultFeedURLStringProvider: () -> String?

    init(
        settingsStore: UpdateSettingsStore = .shared,
        defaultFeedURLStringProvider: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        }
    ) {
        self.settingsStore = settingsStore
        self.defaultFeedURLStringProvider = defaultFeedURLStringProvider
    }

    var defaultFeedURLString: String? {
        Self.normalizedFeedURLString(from: defaultFeedURLStringProvider())
    }

    var resolvedFeedURLString: String? {
        if let custom = Self.normalizedFeedURLString(from: settingsStore.customFeedURLString) {
            return custom
        }
        return defaultFeedURLString
    }

    var resolvedFeedURL: URL? {
        Self.normalizedFeedURL(from: resolvedFeedURLString)
    }

    static func normalizedFeedURLString(from candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        guard url.host?.isEmpty == false else { return nil }
        return url.absoluteString
    }

    static func normalizedFeedURL(from candidate: String?) -> URL? {
        guard let normalized = normalizedFeedURLString(from: candidate) else { return nil }
        return URL(string: normalized)
    }
}
