import Network
import WebKit
import XCTest
@testable import Search

@MainActor
final class ShieldTests: XCTestCase {
    func testNetworkFilterMatchesOnlyTheListedHostAndItsSubdomains() throws {
        let pattern = try NSRegularExpression(pattern: Shield.networkFilter(for: "segment.com"))
        for url in ["https://segment.com/track", "http://segment.com/track",
                    "https://cdn.segment.com/track", "https://a.b.segment.com/track",
                    "https://segment.com:8443/track", "https://segment.com/",
                    "https://segment.com/?event=test", "https://segment.com/#event"] {
            XCTAssertNotNil(pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
        for url in ["https://segment.company/app.js", "https://cdn.segment.company/app.js",
                    "https://segment.com.example/app.js", "https://segment.com-example/app.js",
                    "https://notsegment.com/app.js", "https://example.com/segment.com/track",
                    "https://segmentXcom/app.js", "ftp://segment.com/track"] {
            XCTAssertNil(pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
    }

    func testNetworkFilterCompilesInWebKit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shield-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: folder))
        let rules: [[String: Any]] = [[
            "trigger": ["url-filter": Shield.networkFilter(for: "segment.com"), "load-type": ["third-party"]],
            "action": ["type": "block"],
        ]]
        let data = try JSONSerialization.data(withJSONObject: rules)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let list = try await store.compileContentRuleList(forIdentifier: "fixture", encodedContentRuleList: json)
        XCTAssertNotNil(list)
    }

    // MARK: EasyList, EasyPrivacy, the allowlist

    private func temp() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shield-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Small stand-ins for the two lists: each blocks one path. Keys are
    /// sorted because the store names a list by a hash of its text, and a
    /// dictionary's key order can differ between two writes of one rule.
    private func fixtureLists(_ folder: URL, blocking path: String = "ad\\.js") throws {
        for name in ["easylist", "easyprivacy"] {
            let rule = [["trigger": ["url-filter": name == "easylist" ? path : "track\\.js"],
                         "action": ["type": "block"]]]
            try JSONSerialization.data(withJSONObject: rule, options: .sortedKeys).write(to: folder.appendingPathComponent("\(name).json"))
        }
    }

    func testBundledListsCompileInWebKit() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore(url: try temp()))
        let shield = Shield()
        await shield.build(store: store)
        XCTAssertNil(shield.trouble)
        XCTAssertEqual(shield.lists.count, 3)
        let ids = Set(shield.lists.compactMap(\.identifier))
        XCTAssertTrue(ids.contains { $0.hasPrefix("easylist.") })
        XCTAssertTrue(ids.contains { $0.hasPrefix("easyprivacy.") })
    }

    func testUnchangedListsComeFromTheStoreAndChangedOnesReplaceTheOld() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore(url: try temp()))
        let folder = try temp()
        try fixtureLists(folder)
        let first = Shield()
        await first.build(store: store, blocklists: folder)
        XCTAssertEqual(first.lists.count, 3)
        XCTAssertEqual(first.reused, 0)
        let before = Set(await store.availableIdentifiers() ?? [])

        let second = Shield()
        await second.build(store: store, blocklists: folder)
        XCTAssertEqual(second.reused, 3)
        let same = Set(await store.availableIdentifiers() ?? [])
        XCTAssertEqual(same, before)

        try fixtureLists(folder, blocking: "other\\.js")
        let third = Shield()
        await third.build(store: store, blocklists: folder)
        XCTAssertEqual(third.reused, 2)
        let after = Set(await store.availableIdentifiers() ?? [])
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(before.subtracting(after).count, 1)
    }

    /// A tiny local server: `/` is a page that fetches `/ad.js` and writes the
    /// outcome to its title; everything else is an empty 200.
    private func serve() throws -> (NWListener, UInt16) {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let head = String(decoding: data ?? Data(), as: UTF8.self)
                let isPage = head.hasPrefix("GET / ")
                let body = isPage
                    ? "<script>fetch('/ad.js').then(() => document.title = 'loaded', () => document.title = 'blocked')</script>"
                    : ""
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: \(isPage ? "text/html" : "text/plain")\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        wait(for: [ready], timeout: 5)
        addTeardownBlock { listener.cancel() }
        return (listener, try XCTUnwrap(listener.port?.rawValue))
    }

    private func outcome(of shield: Shield, port: UInt16) async throws -> String {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        shield.tune(webView.configuration.userContentController, for: "127.0.0.1")
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let title = try? await webView.evaluateJavaScript("document.title") as? String, !title.isEmpty {
                return title
            }
        }
        return "timeout"
    }

    func testPausedSiteIsNotBlockedAndOthersAre() async throws {
        let (_, port) = try serve()
        let folder = try temp()
        try fixtureLists(folder)
        let shield = Shield()
        await shield.build(store: try XCTUnwrap(WKContentRuleListStore(url: try temp())), blocklists: folder)

        let blocked = try await outcome(of: shield, port: port)
        XCTAssertEqual(blocked, "blocked")

        shield.pause("127.0.0.1", true)
        addTeardownBlock { MainActor.assumeIsolated { shield.pause("127.0.0.1", false) } }
        let allowed = try await outcome(of: shield, port: port)
        XCTAssertEqual(allowed, "loaded")
    }
}
