import Foundation

enum RepoTabKind: String, Codable, CaseIterable {
    case git
    case workbench

    var symbol: String { self == .git ? "arrow.triangle.branch" : "square.stack.3d.up" }
}

struct RepoTab: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String
    var kind: RepoTabKind = .git

    var displayName: String { kind == .workbench ? "\(name) · Workbench" : name }
}

struct SavedTab: Codable, Equatable {
    let path: String
    let name: String
    let kind: RepoTabKind
}

enum TabPersistence {
    static func decode(current: Data?, legacy: Data?) -> [SavedTab] {
        if let current, let tabs = try? JSONDecoder().decode([SavedTab].self, from: current) {
            return tabs
        }
        guard let legacy, let repos = try? JSONDecoder().decode([SavedRepo].self, from: legacy) else { return [] }
        return repos.map { SavedTab(path: $0.path, name: $0.name, kind: .git) }
    }
}

struct SavedRepo: Codable, Equatable {
    let path: String
    let name: String
}
