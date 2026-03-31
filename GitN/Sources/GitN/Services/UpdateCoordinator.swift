import AppKit
import Foundation
import Sparkle

@MainActor
@Observable
final class UpdateCoordinator: NSObject {
    enum AvailabilityState: Equatable {
        case unavailable
        case idle
        case checking
        case updateAvailable(version: String)
        case upToDate
        case downloaded(version: String)
        case error(message: String)
    }

    private let settingsStore: UpdateSettingsStore
    private let feedResolver: UpdateFeedResolver
    private let bundleConfiguration: UpdateConfiguration
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    var canCheckForUpdates = false
    var automaticChecksEnabled = false
    var automaticDownloadsEnabled = false
    var lastUpdateCheckDate: Date?
    var availabilityState: AvailabilityState = .idle

    init(
        settingsStore: UpdateSettingsStore = .shared,
        bundle: Bundle = .main
    ) {
        self.settingsStore = settingsStore
        self.bundleConfiguration = UpdateConfiguration(
            defaultFeedURLString: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicEDKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
        self.feedResolver = UpdateFeedResolver(
            settingsStore: settingsStore,
            defaultFeedURLStringProvider: {
                bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
            }
        )
        super.init()
    }

    var currentFeedURLString: String {
        settingsStore.customFeedURLString
    }

    var effectiveFeedURLString: String {
        feedResolver.resolvedFeedURLString ?? ""
    }

    var defaultFeedURLString: String {
        feedResolver.defaultFeedURLString ?? ""
    }

    var configurationProblemDescription: String? {
        guard bundleConfiguration.isPublicKeyConfigured else {
            return "Sparkle public key is missing from the app bundle."
        }
        guard feedResolver.resolvedFeedURL != nil else {
            return "No valid appcast feed URL is configured."
        }
        return nil
    }

    var isAvailable: Bool {
        configurationProblemDescription == nil
    }

    var availabilityDescription: String {
        switch availabilityState {
        case .unavailable:
            return configurationProblemDescription ?? "Updates are unavailable."
        case .idle:
            return "Ready to check for updates."
        case .checking:
            return "Checking for updates..."
        case let .updateAvailable(version):
            return "Update \(version) is available."
        case .upToDate:
            return "You are already on the latest version."
        case let .downloaded(version):
            return "Update \(version) was downloaded and will install when GitN quits."
        case let .error(message):
            return message
        }
    }

    func start() {
        guard updaterController == nil else { return }

        guard isAvailable else {
            availabilityState = .unavailable
            canCheckForUpdates = false
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller

        controller.startUpdater()
        _ = controller.updater.clearFeedURLFromUserDefaults()

        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }

        refreshPreferencesFromUpdater()
    }

    func checkForUpdates() {
        guard let updater = updaterController?.updater, isAvailable else {
            availabilityState = .unavailable
            return
        }
        availabilityState = .checking
        updater.checkForUpdates()
    }

    func saveCustomFeedURL(_ candidate: String) {
        let previousFeed = feedResolver.resolvedFeedURLString
        let normalized = settingsStore.saveCustomFeedURLString(candidate)
        if normalized.isEmpty {
            availabilityState = .idle
        }

        if previousFeed != feedResolver.resolvedFeedURLString {
            resetUpdateCycleIfPossible()
        }

        if updaterController == nil, isAvailable {
            start()
        } else if !isAvailable {
            availabilityState = .unavailable
        }
    }

    func clearCustomFeedURL() {
        let previousFeed = feedResolver.resolvedFeedURLString
        settingsStore.clearCustomFeedURL()

        if previousFeed != feedResolver.resolvedFeedURLString {
            resetUpdateCycleIfPossible()
        }

        if isAvailable {
            availabilityState = .idle
        } else {
            availabilityState = .unavailable
        }
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else {
            automaticChecksEnabled = isEnabled
            return
        }
        updater.automaticallyChecksForUpdates = isEnabled
        automaticChecksEnabled = updater.automaticallyChecksForUpdates
    }

    func setAutomaticDownloadsEnabled(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else {
            automaticDownloadsEnabled = isEnabled
            return
        }
        updater.automaticallyDownloadsUpdates = isEnabled
        automaticDownloadsEnabled = updater.automaticallyDownloadsUpdates
    }

    private func refreshPreferencesFromUpdater() {
        guard let updater = updaterController?.updater else { return }
        automaticChecksEnabled = updater.automaticallyChecksForUpdates
        automaticDownloadsEnabled = updater.automaticallyDownloadsUpdates
    }

    private func resetUpdateCycleIfPossible() {
        guard let updater = updaterController?.updater else { return }
        updater.resetUpdateCycleAfterShortDelay()
    }

    private func versionLabel(for item: SUAppcastItem) -> String {
        if !item.displayVersionString.isEmpty {
            return item.displayVersionString
        }
        return item.versionString
    }
}

extension UpdateCoordinator: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        feedResolver.resolvedFeedURLString
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availabilityState = .updateAvailable(version: versionLabel(for: item))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availabilityState = .upToDate
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        availabilityState = .downloaded(version: versionLabel(for: item))
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        availabilityState = .error(message: error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        availabilityState = .error(message: error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastUpdateCheckDate = Date()
        refreshPreferencesFromUpdater()
        if let error {
            let nsError = error as NSError
            if nsError.domain == SUSparkleErrorDomain, nsError.code == 1001 {
                availabilityState = .upToDate
            } else {
                availabilityState = .error(message: error.localizedDescription)
            }
        } else if case .checking = availabilityState {
            availabilityState = .idle
        }
    }
}
