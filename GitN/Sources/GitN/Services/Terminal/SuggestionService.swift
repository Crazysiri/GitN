import Foundation
import Observation

/// Produces suggestions for one terminal session. Each request is keyed by
/// session + cwd + promptGeneration + inputRevision; late results from a
/// superseded request are dropped so suggestions never "cross" input states
/// (SPEC §7.2). Providers are read-only and never execute user input.
@MainActor
final class SuggestionService {
    struct Result: Equatable {
        let request: SuggestionRequest
        let suggestions: [CommandSuggestion]
        /// Character-offset range the accepted suggestion replaces.
        let replacementRange: Range<Int>?
    }

    private var latestRevision: Int = -1
    private var currentTask: Task<Void, Never>?

    /// Called on the main actor with results for the newest request only.
    var onResult: ((Result) -> Void)?

    func request(_ request: SuggestionRequest) {
        // Supersede any in-flight request.
        latestRevision = request.inputRevision
        currentTask?.cancel()

        let plan = SuggestionEngine.plan(line: request.line, cursor: request.cursor)

        // Static suggestions resolve immediately.
        if plan.dynamicNeed == .none {
            deliver(request: request, suggestions: plan.staticSuggestions, range: plan.replacementRange)
            return
        }

        // Dynamic needs run off the main actor, then filter by prefix.
        let need = plan.dynamicNeed
        let cwd = request.cwd
        let prefix = plan.prefix
        let range = plan.replacementRange
        let revision = request.inputRevision

        currentTask = Task { [weak self] in
            let dynamic = await Self.fetchDynamic(need: need, cwd: cwd, prefix: prefix)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self, self.latestRevision == revision else { return }
                self.deliver(request: request, suggestions: plan.staticSuggestions + dynamic, range: range)
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func deliver(request: SuggestionRequest, suggestions: [CommandSuggestion], range: Range<Int>?) {
        guard latestRevision == request.inputRevision else { return }
        onResult?(Result(request: request, suggestions: suggestions, replacementRange: range))
    }

    private static func fetchDynamic(
        need: SuggestionEngine.DynamicNeed,
        cwd: String,
        prefix: String
    ) async -> [CommandSuggestion] {
        switch need {
        case .none:
            return []
        case .directories:
            return SuggestionProviders.directories(cwd: cwd, prefix: prefix)
        case .gitBranches:
            return await SuggestionProviders.gitBranches(cwd: cwd, prefix: prefix)
        case .gitFiles:
            return await SuggestionProviders.gitFiles(cwd: cwd, prefix: prefix)
        case .packageScripts:
            return SuggestionProviders.packageScripts(cwd: cwd, prefix: prefix)
        }
    }
}
