import XCTest
@testable import Search

/// Link routing's matching, order, fallback and file, on made-up rules and a
/// temporary folder rather than the user's.
final class LinkRouterTests: XCTestCase {
    private let work = UUID()
    private func url(_ text: String) -> URL { URL(string: text)! }
    private func go(_ text: String, _ rules: [LinkRule], spaces: Set<UUID> = []) -> LinkDestination? {
        LinkRouter.route(url(text), rules: rules) { spaces.contains($0) }
    }

    func testExactAndCaseAndPort() {
        let rules = [LinkRule(pattern: "GitHub.com", target: .little)]
        XCTAssertEqual(go("https://github.com/a", rules), .little)
        XCTAssertEqual(go("https://GITHUB.COM:8443/a", rules), .little)
        XCTAssertEqual(go("https://github.com./a", rules), .little)
        XCTAssertNil(go("https://gist.github.com/a", rules))
        XCTAssertEqual(go("https://x.org/", [LinkRule(pattern: "x.org:8080", target: .little)]), .little)
    }

    func testWildcardIsSubdomainsOnly() {
        let rules = [LinkRule(pattern: "*.github.com", target: .little)]
        XCTAssertEqual(go("https://gist.github.com/", rules), .little)
        XCTAssertEqual(go("https://a.b.github.com/", rules), .little)
        XCTAssertNil(go("https://github.com/", rules))
        XCTAssertNil(go("https://evilgithub.com/", rules))
        XCTAssertNil(go("https://github.com.evil.com/", rules))
    }

    func testInternationalHosts() {
        XCTAssertTrue(LinkRouter.matches(pattern: "bücher.de", host: "xn--bcher-kva.de"))
        XCTAssertTrue(LinkRouter.matches(pattern: "xn--bcher-kva.de", host: "BÜCHER.de"))
        XCTAssertTrue(LinkRouter.matches(pattern: "*.bücher.de", host: "shop.xn--bcher-kva.de"))
        XCTAssertFalse(LinkRouter.matches(pattern: "bücher.de", host: "bucher.de"))
    }

    func testFirstMatchWinsInOrder() {
        let a = LinkRule(pattern: "*.github.com", target: .little)
        let b = LinkRule(pattern: "gist.github.com", target: .space(work))
        XCTAssertEqual(go("https://gist.github.com/", [a, b], spaces: [work]), .little)
        XCTAssertEqual(go("https://gist.github.com/", [b, a], spaces: [work]), .space(work))
    }

    func testDeletedSpaceFallsBackToCurrent() {
        let rules = [LinkRule(pattern: "github.com", target: .space(work))]
        XCTAssertEqual(go("https://github.com/", rules, spaces: [work]), .space(work))
        XCTAssertEqual(go("https://github.com/", rules, spaces: []), .current)
    }

    func testNoRuleAndNonWebLinks() {
        XCTAssertNil(go("https://example.com/", []))
        XCTAssertNil(go("file:///tmp/a.html", [LinkRule(pattern: "tmp", target: .little)]))
    }

    func testRulesRoundTripPerProfileAndCorruptFileIsEmpty() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("linkrules-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let me = UUID(), other = UUID()
        let rules = [LinkRule(pattern: "github.com", target: .space(work)),
                     LinkRule(pattern: "*.zoom.us", target: .little),
                     LinkRule(pattern: "x.org", target: .current)]
        XCTAssertEqual(LinkRules.read(profile: me, in: folder), [])
        LinkRules.write(rules, profile: me, in: folder)
        XCTAssertEqual(LinkRules.read(profile: me, in: folder), rules)
        XCTAssertEqual(LinkRules.read(profile: other, in: folder), [])
        try Data("{not json".utf8).write(to: LinkRules.file(profile: me, in: folder))
        XCTAssertEqual(LinkRules.read(profile: me, in: folder), [])
        let bogus = "[{\"id\":\"\(UUID())\",\"pattern\":\"a.com\",\"target\":\"bogus\"}]"
        try Data(bogus.utf8).write(to: LinkRules.file(profile: me, in: folder))
        XCTAssertEqual(LinkRules.read(profile: me, in: folder), [])
    }
}
