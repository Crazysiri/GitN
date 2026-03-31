import XCTest
@testable import GitN

final class UpdateSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UpdateSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSavingCustomFeedNormalizesAndPersistsURL() {
        let store = UpdateSettingsStore(defaults: defaults)

        let saved = store.saveCustomFeedURLString("  https://updates.example.com/appcast.xml  ")

        XCTAssertEqual(saved, "https://updates.example.com/appcast.xml")
        XCTAssertEqual(store.customFeedURLString, "https://updates.example.com/appcast.xml")
        XCTAssertEqual(store.customFeedURL?.absoluteString, "https://updates.example.com/appcast.xml")
    }

    func testSavingInvalidFeedClearsOverride() {
        let store = UpdateSettingsStore(defaults: defaults)
        _ = store.saveCustomFeedURLString("https://updates.example.com/appcast.xml")

        let saved = store.saveCustomFeedURLString("not a url")

        XCTAssertEqual(saved, "")
        XCTAssertEqual(store.customFeedURLString, "")
        XCTAssertNil(store.customFeedURL)
    }

    func testFeedResolverPrefersCustomFeedOverBundleFeed() {
        let store = UpdateSettingsStore(defaults: defaults)
        _ = store.saveCustomFeedURLString("https://cdn.example.com/custom.xml")
        let resolver = UpdateFeedResolver(
            settingsStore: store,
            defaultFeedURLStringProvider: { "https://example.com/default.xml" }
        )

        XCTAssertEqual(resolver.resolvedFeedURLString, "https://cdn.example.com/custom.xml")
    }

    func testFeedResolverFallsBackToBundleFeed() {
        let store = UpdateSettingsStore(defaults: defaults)
        let resolver = UpdateFeedResolver(
            settingsStore: store,
            defaultFeedURLStringProvider: { "https://example.com/default.xml" }
        )

        XCTAssertEqual(resolver.resolvedFeedURLString, "https://example.com/default.xml")
    }
}
