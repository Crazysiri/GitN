import Foundation

enum CodeHostingReviewCreationURLBuilder {
    static func buildURL(
        provider: CodeHostingProvider,
        remoteURL: String,
        sourceBranch: String
    ) -> URL? {
        let trimmedBranch = sourceBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty else { return nil }

        guard
            let host = CodeHostingRemote.parseHost(from: remoteURL),
            let repositoryPath = CodeHostingRemote.parseRepositoryPath(from: remoteURL)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            !repositoryPath.isEmpty
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host

        switch provider {
        case .gitlab:
            components.percentEncodedPath = "/" + repositoryPath + "/-/merge_requests/new"
            components.queryItems = [
                URLQueryItem(name: "merge_request[source_branch]", value: trimmedBranch)
            ]
            return components.url
        case .github:
            components.percentEncodedPath = "/" + repositoryPath + "/compare/" + percentEncodePathComponent(trimmedBranch)
            components.queryItems = [
                URLQueryItem(name: "expand", value: "1")
            ]
            return components.url
        case .unknown:
            return nil
        }
    }

    private static func percentEncodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
