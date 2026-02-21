import SwiftUI
import Combine

@Observable
final class AppModel {
    var tabs: [RepoTab] = []
    var selectedTabID: UUID?

    private static let savedReposKey = "GitX.savedRepos"

    var selectedTab: RepoTab? {
        tabs.first { $0.id == selectedTabID }
    }

    init() {
        restoreSavedRepos()
    }

    func openRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent
        let tab = RepoTab(path: url.path, name: name)
        tabs.append(tab)
        selectedTabID = tab.id
        persistRepos()
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
        persistRepos()
    }

    func addTab(path: String, name: String) {
        if let existing = tabs.first(where: { $0.path == path }) {
            selectedTabID = existing.id
            return
        }
        let tab = RepoTab(path: path, name: name)
        tabs.append(tab)
        selectedTabID = tab.id
        persistRepos()
    }

    // MARK: - Persistence

    private func persistRepos() {
        let saved = tabs.map { SavedRepo(path: $0.path, name: $0.name) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedReposKey)
        }
    }

    private func restoreSavedRepos() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedReposKey),
              let saved = try? JSONDecoder().decode([SavedRepo].self, from: data),
              !saved.isEmpty
        else { return }

        for repo in saved {
            let tab = RepoTab(path: repo.path, name: repo.name)
            tabs.append(tab)
        }
        selectedTabID = tabs.first?.id
    }
}
