import AVFoundation
import CoreVideo
import XCTest
@testable import GitN

/// Tests for `VideoPreviewController` — the `AVPlayer` lifecycle owner used by the
/// video preview. These exercise the controller directly (no SwiftUI view body is
/// instantiated) and assert the load state machine plus teardown side-effects.
///
/// Covered requirements:
/// - R1.3: decodable bytes resolve to `.ready`; garbage bytes resolve to `.failed`.
/// - R1.5: a freshly loaded asset is paused at time zero (player never auto-plays).
/// - R1.6: `teardown()` releases the player and deletes the backing temp file.
/// - R1.8: the lifecycle is verified without instantiating any SwiftUI view body.
@MainActor
final class VideoPreviewControllerTests: XCTestCase {

    /// Prefix used by `VideoPreviewController` for its temporary files (matches
    /// `makeTemporaryURL` in the implementation under test).
    private let tempFilePrefix = "gitn_video_"

    // MARK: - R1.3 / R1.5: decodable data -> .ready, paused at time zero

    func testDecodableVideoDataTransitionsToReady() async throws {
        let movieData = try makePlayableMovieData()

        let controller = VideoPreviewController()
        defer { controller.teardown() }

        controller.load(data: movieData, fileExtension: "mov")
        await waitUntilLeavesLoading(controller)

        XCTAssertEqual(controller.state, .ready, "Decodable video bytes should resolve to .ready")
        XCTAssertNotNil(controller.player, "A ready video should have an AVPlayer")
        // R1.5: the player must be paused at time zero — load() never calls play().
        XCTAssertEqual(controller.player?.rate, 0, "Newly loaded video must be paused (rate == 0)")
    }

    // MARK: - R1.3: garbage data -> .failed

    func testGarbageBytesTransitionToFailed() async {
        let controller = VideoPreviewController()
        defer { controller.teardown() }

        var garbage = Data(count: 4096)
        garbage.withUnsafeMutableBytes { buffer in
            for index in buffer.indices {
                buffer[index] = UInt8.random(in: .min ... .max)
            }
        }

        controller.load(data: garbage, fileExtension: "mp4")
        await waitUntilLeavesLoading(controller)

        XCTAssertEqual(controller.state, .failed, "Undecodable bytes should resolve to .failed")
    }

    // MARK: - R1.6: teardown releases the player and deletes the temp file

    func testTeardownReleasesPlayerAndDeletesTempFile() async throws {
        let movieData = try makePlayableMovieData()

        // Snapshot the temp files owned by the controller before loading so we can
        // identify the file this load creates without reading the private `tempURL`.
        let before = controllerTempFiles()

        let controller = VideoPreviewController()
        controller.load(data: movieData, fileExtension: "mov")
        await waitUntilLeavesLoading(controller)
        XCTAssertEqual(controller.state, .ready)

        let createdDuringLoad = controllerTempFiles().subtracting(before)
        XCTAssertFalse(
            createdDuringLoad.isEmpty,
            "load() should write a temporary \(tempFilePrefix)* file"
        )

        controller.teardown()

        XCTAssertNil(controller.player, "teardown() must release the AVPlayer")
        XCTAssertEqual(controller.state, .idle, "teardown() returns the controller to .idle")

        let remaining = controllerTempFiles()
        XCTAssertTrue(
            createdDuringLoad.isDisjoint(with: remaining),
            "teardown() must delete the temporary file it created"
        )
    }

    // MARK: - Helpers

    /// Awaits until the controller's load state machine leaves `.loading`.
    ///
    /// `load(...)` flips `state` to `.loading` synchronously, then resolves to
    /// `.ready`/`.failed` from a `Task { @MainActor in ... }`. Because the test and
    /// the controller share the main actor, suspending here lets that task run.
    private func waitUntilLeavesLoading(
        _ controller: VideoPreviewController,
        timeout: TimeInterval = 10
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.state == .loading, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    /// Names of the temporary files the controller creates (prefix `gitn_video_`)
    /// currently present in the system temporary directory.
    private func controllerTempFiles() -> Set<String> {
        let tempDir = FileManager.default.temporaryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        return Set(contents.filter { $0.hasPrefix(tempFilePrefix) })
    }

    /// Generates a tiny but valid, playable H.264 `.mov` and returns its bytes.
    ///
    /// Building the asset at runtime keeps the test self-contained (no checked-in
    /// binary fixture) and deterministic. If the platform cannot provide an H.264
    /// encoder, the test is skipped with a clear message rather than failing.
    private func makePlayableMovieData() throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitn_test_movie_\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let width = 16
        let height = 16
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw XCTSkip("AVAssetWriter cannot add an H.264 video input in this environment")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw XCTSkip("AVAssetWriter failed to start (no H.264 encoder available): \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = 6
        let timescale: CMTimeScale = 30
        for frameIndex in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            let pixelBuffer = try makeBlackPixelBuffer(width: width, height: height)
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: timescale)
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: presentationTime))
        }
        input.markAsFinished()

        // finishWriting is asynchronous; block until it completes. Its completion
        // runs on an internal queue, so waiting on the main thread is safe here.
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            throw XCTSkip("AVAssetWriter did not complete writing: \(String(describing: writer.error))")
        }

        return try Data(contentsOf: outputURL)
    }

    /// Creates a single black `kCVPixelFormatType_32ARGB` pixel buffer.
    private func makeBlackPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw XCTSkip("Unable to allocate CVPixelBuffer (status \(status))")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            memset(base, 0, bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
