import AVFoundation
import Foundation

/// Owns the `AVPlayer` lifecycle for a single video preview.
///
/// The controller is intentionally decoupled from any SwiftUI view body so its
/// state machine and teardown side-effects can be unit-tested by instantiating
/// the type directly, feeding it `Data`, and asserting `state` / `player`.
///
/// Lifecycle contract (see Requirements R1.3 / R1.5 / R1.6):
/// - `load(data:fileExtension:)` writes the bytes to a temp file, builds an
///   `AVURLAsset`, validates playability, and transitions `state` to `.ready`
///   or `.failed`. The player is created paused at time zero; `play()` is never
///   called here.
/// - `teardown()` releases resources in a fixed order: pause the player,
///   detach/release it, then delete the temp file.
@MainActor
final class VideoPreviewController: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    @Published private(set) var state: LoadState = .idle

    /// The backing player. Created paused at time zero on a successful load and
    /// released (set to `nil`) by `teardown()`. (R1.5/R1.6)
    private(set) var player: AVPlayer?

    /// URL of the temporary file backing the current asset, if any.
    private var tempURL: URL?

    /// Monotonic token used to discard results from a superseded `load(...)`
    /// call so a late-arriving playability check cannot overwrite newer state.
    private var loadGeneration: Int = 0

    init() {}

    /// Loads `data` as a video by writing it to a temporary file and validating
    /// that the resulting asset is playable.
    ///
    /// Any previously loaded asset is torn down first. `state` becomes `.loading`
    /// synchronously, then `.ready` (playable) or `.failed` (not playable / error)
    /// once the asynchronous playability check resolves on the main actor. (R1.3)
    func load(data: Data, fileExtension: String) {
        // Release any prior asset/player and temp file before starting fresh.
        teardown()

        loadGeneration += 1
        let token = loadGeneration
        state = .loading

        let url = Self.makeTemporaryURL(fileExtension: fileExtension)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            state = .failed
            return
        }
        tempURL = url

        let asset = AVURLAsset(url: url)
        Task { @MainActor in
            await self.finishLoading(asset: asset, token: token)
        }
    }

    /// Releases all resources in the required order (R1.6):
    /// pause the player, detach/release it (`player = nil`), then delete the
    /// temporary file. Leaves the controller in the `.idle` state.
    func teardown() {
        player?.pause()
        player = nil
        removeTempFile()
        state = .idle
    }

    deinit {
        // `deinit` cannot hop to the main actor, so perform a best-effort,
        // synchronous subset of `teardown()`: pause + release the player and
        // delete the temp file via the captured URL.
        player?.pause()
        player = nil
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }

    // MARK: - Private

    private func finishLoading(asset: AVURLAsset, token: Int) async {
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            // Discard if a newer load (or teardown) superseded this one.
            guard token == loadGeneration else { return }
            state = .failed
            return
        }

        // Discard if a newer load (or teardown) superseded this one.
        guard token == loadGeneration else { return }

        guard isPlayable else {
            state = .failed
            return
        }

        // Build the player paused at time zero — never call `play()` here. (R1.5)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        state = .ready
    }

    private func removeTempFile() {
        guard let url = tempURL else { return }
        try? FileManager.default.removeItem(at: url)
        tempURL = nil
    }

    private static func makeTemporaryURL(fileExtension: String) -> URL {
        let normalizedExtension = fileExtension.hasPrefix(".")
            ? String(fileExtension.dropFirst())
            : fileExtension
        var fileName = "gitn_video_\(UUID().uuidString)"
        if !normalizedExtension.isEmpty {
            fileName += ".\(normalizedExtension)"
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
