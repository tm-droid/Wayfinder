//
//  ContentBlockerTests.swift
//  WayfinderTests
//

import XCTest
import WebKit
@testable import Wayfinder

final class ContentBlockerAllowlistTests: XCTestCase {
    func testExactAndSubdomainMatch() {
        let list = ["example.com"]
        XCTAssertTrue(ContentBlocker.isAllowlisted(host: "example.com", in: list))
        XCTAssertTrue(ContentBlocker.isAllowlisted(host: "www.example.com", in: list))
        XCTAssertTrue(ContentBlocker.isAllowlisted(host: "A.B.Example.com.", in: list))
    }

    func testNoPartialLabelMatch() {
        let list = ["example.com"]
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "notexample.com", in: list))
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "example.com.evil.net", in: list))
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "com", in: list))
    }

    func testEmptyInputs() {
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "", in: ["example.com"]))
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "example.com", in: []))
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "example.com", in: [""]))
    }

    func testSubdomainEntryDoesNotCoverParent() {
        XCTAssertFalse(ContentBlocker.isAllowlisted(host: "example.com", in: ["www.example.com"]))
    }
}

@MainActor
final class ContentBlockerTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ContentBlockerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeBlocker(name: String = UUID().uuidString) -> ContentBlocker {
        ContentBlocker(defaults: defaults,
                       file: JSONFile(name: "BlockerAllowlistTest-\(name).json"),
                       store: WKContentRuleListStore(url: directory),
                       bundle: Bundle(for: ContentBlocker.self))
    }

    private func bundledJSON(_ name: String) throws -> Data {
        let bundle = Bundle(for: ContentBlocker.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Blocklists")
                                ?? bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testBundledListsParseAndStayUnderCap() throws {
        for name in ContentBlocker.listNames {
            let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledJSON(name)) as? [[String: Any]])
            XCTAssertGreaterThan(rules.count, 1000, name)
            XCTAssertLessThanOrEqual(rules.count, 150_000, name)
        }
    }

    func testStoreCompilesSampleRules() async throws {
        let sample = """
        [{"trigger":{"url-filter":"^[^:]+:(//)?([^/]+\\\\.)?ads\\\\.example\\\\.com[/:?#]","resource-type":["script","raw","fetch"],"load-type":["third-party"],"if-domain":["*a.com"]},"action":{"type":"block"}},
         {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad, div[id^=\\"sponsor\\"]"}},
         {"trigger":{"url-filter":"^[^:]+:(//)?([^/]+\\\\.)?ok\\\\.com"},"action":{"type":"ignore-previous-rules"}}]
        """
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory))
        let list = await ContentBlocker.compile(sample, identifier: "test.sample", in: store)
        XCTAssertNotNil(list)
        // Second call hits the cache.
        let again = await ContentBlocker.compile("not json", identifier: "test.sample", in: store)
        XCTAssertNotNil(again)
    }

    func testRealListsCompile() async throws {
        let blocker = makeBlocker()
        let lists = await blocker.rules()
        XCTAssertEqual(lists.count, ContentBlocker.listNames.count)
    }

    func testEnableDisableApply() async throws {
        let blocker = makeBlocker()
        let controller = WKUserContentController()
        _ = await blocker.rules()

        blocker.isEnabled = false
        XCTAssertEqual(defaults.object(forKey: ContentBlocker.enabledKey) as? Bool, false)
        blocker.apply(to: controller, for: "example.com")
        // No public getter for rule lists; verify via re-apply behaviour not throwing and flag persisted.

        let reloaded = ContentBlocker(defaults: defaults, file: JSONFile(name: "BlockerAllowlistTest-x.json"),
                                      store: nil, bundle: .main)
        XCTAssertFalse(reloaded.isEnabled)

        blocker.isEnabled = true
        blocker.apply(to: controller, for: "example.com")
        blocker.apply(to: controller, for: "example.com")
        blocker.setAllowlisted(true, host: "example.com")
        XCTAssertTrue(blocker.isAllowlisted("www.example.com"))
        blocker.apply(to: controller, for: "www.example.com")
        blocker.setAllowlisted(false, host: "www.example.com")
        XCTAssertFalse(blocker.isAllowlisted("example.com"))
    }

    func testAllowlistPersists() {
        let name = UUID().uuidString
        let first = makeBlocker(name: name)
        first.setAllowlisted(true, host: "Example.com")
        first.setAllowlisted(true, host: "example.com")
        XCTAssertEqual(first.allowlist, ["example.com"])
        let second = makeBlocker(name: name)
        XCTAssertEqual(second.allowlist, ["example.com"])
        try? FileManager.default.removeItem(at: JSONFile<[String]>(name: "BlockerAllowlistTest-\(name).json").url)
    }

    func testDefaultsToEnabled() {
        XCTAssertTrue(makeBlocker().isEnabled)
    }
}
