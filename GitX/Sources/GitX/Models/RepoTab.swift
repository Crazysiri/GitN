import Foundation

struct RepoTab: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String
}

struct SavedRepo: Codable, Equatable {
    let path: String
    let name: String
}
