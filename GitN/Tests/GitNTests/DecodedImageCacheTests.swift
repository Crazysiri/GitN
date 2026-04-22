import XCTest
import AppKit
@testable import GitN

final class DecodedImageCacheTests: XCTestCase {
    private let onePixelPNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN6kAAAAASUVORK5CYII=")!
    private let otherPixelPNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAABAcne9AAAADElEQVR42mP8z8AARAAA//8DAF0BB6o9jwAAAABJRU5ErkJggg==")!

    func testCacheKeyIsStableForSameData() {
        let cache = DecodedImageCache.shared

        XCTAssertEqual(cache.cacheKey(for: onePixelPNGData), cache.cacheKey(for: onePixelPNGData))
    }

    func testCacheKeyDiffersForDifferentData() {
        let cache = DecodedImageCache.shared

        XCTAssertNotEqual(cache.cacheKey(for: onePixelPNGData), cache.cacheKey(for: otherPixelPNGData))
    }

    func testImageLookupReturnsCachedInstanceForSameData() {
        let cache = DecodedImageCache.shared

        let first = cache.image(for: onePixelPNGData)
        let second = cache.image(for: onePixelPNGData)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }
}
