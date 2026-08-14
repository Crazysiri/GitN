import AVFoundation
import AVKit
import SwiftUI

/// Renders a video `VisualFileContent` in the file inspector.
///
/// The view is intentionally thin: all `AVPlayer` lifecycle logic lives in the
/// testable ``VideoPreviewController``. This view only wires the controller's
/// observable `state` to SwiftUI:
/// - `.ready`  → a `VideoPlayer` surface. AVKit's built-in transport already
///   provides the play/pause toggle, a full-duration scrub bar, and a
///   current-time/total-duration label. (R1.4)
/// - `.failed` → the shared binary placeholder with an "Unsupported video"
///   message that never exposes internal error codes or stack details. (R1.3)
///
/// Bytes come from ``VisualFileContent/currentData`` (`newData ?? oldData`), so
/// deletion entries fall back to the pre-image bytes. (R1.2)
struct VideoDiffContentView: View {
    let content: VisualFileContent
    let path: String

    @StateObject private var controller = VideoPreviewController()

    var body: some View {
        Group {
            if content.currentData == nil {
                unsupportedPlaceholder
            } else {
                switch controller.state {
                case .ready:
                    if let player = controller.player {
                        VideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        unsupportedPlaceholder
                    }
                case .failed:
                    unsupportedPlaceholder
                case .idle, .loading:
                    loadingState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChromePalette.panelBackground)
        .onAppear { load() }
        .onChange(of: path) { _, _ in load() }
        .onDisappear { controller.teardown() }
    }

    private var unsupportedPlaceholder: some View {
        BinaryFilePlaceholderView(
            title: "Unsupported video",
            message: "This video can't be played in GitN."
        )
    }

    private var loadingState: some View {
        ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        guard let data = content.currentData else {
            controller.teardown()
            return
        }
        controller.load(data: data, fileExtension: (path as NSString).pathExtension)
    }
}
