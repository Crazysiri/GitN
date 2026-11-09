import Foundation

struct WorkbenchChanges: Sendable {
    let status: String
    let patch: String
    let capturedAt: Date
}

struct WorkbenchChangesService: Sendable {
    func baseline(path: String) async throws -> TaskWorktreeLink {
        let cli = GitCLI(repoPath: path)
        // Fail for missing/non-repository paths, but allow unborn branches.
        _ = try await cli.output(["rev-parse", "--show-toplevel"])
        let result = try await cli.capture(["rev-parse", "--verify", "HEAD"])
        return TaskWorktreeLink(path: WorktreeService.canonicalPath(path), baseCommit: result.exitCode == 0
            ? String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }

    func changes(link: TaskWorktreeLink) async throws -> WorkbenchChanges {
        let cli = GitCLI(repoPath: link.path)
        let env = ["GIT_OPTIONAL_LOCKS": "0"]
        async let status = cli.output(["-c", "core.quotePath=true", "status", "--short", "--untracked-files=normal"], env: env)
        let options = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--submodule=short"]
        let patch: String
        if let base = link.baseCommit {
            patch = try await cli.output(options + [base, "--"], env: env)
        } else {
            async let staged = cli.output(options + ["--cached", "--"], env: env)
            async let unstaged = cli.output(options + ["--"], env: env)
            patch = try await staged + unstaged
        }
        return try await WorkbenchChanges(status: status, patch: Self.preview(patch), capturedAt: Date())
    }

    private static func preview(_ text: String) -> String {
        let limit = 160_000
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n\nPreview truncated. Open this Worktree in Git to inspect individual files."
    }
}
