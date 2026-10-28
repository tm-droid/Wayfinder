import AppKit
import Network
import WebKit
import XCTest
@testable import Search

/// What Search must not lose or leak however fast it is used: tabs across
/// spaces, what sleeps, what the blocker pauses, what a private tab keeps,
/// and the stores of what is deleted. A test world of its own throughout;
/// files that need a path are in a temp folder.
@MainActor
final class RobustnessTests: XCTestCase {
    private var browser: Browser!
    private var restore: [() -> Void] = []

    override class func setUp() {
        setenv("SEARCH_PROBE", "w13-robust-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        _ = NSApplication.shared
        XCTAssertTrue(Store.testing, "These tests must never touch the real user's files")
        browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let (spaces, sleeps) = (prefs.usesSpaces, prefs.sleepsTabs)
        restore.append { prefs.usesSpaces = spaces; prefs.sleepsTabs = sleeps }
        let saved = Spaces.read()
        restore.append { Spaces.write(saved) }
    }

    override func tearDown() {
        browser.closeAll()
        browser = nil
        restore.reversed().forEach { $0() }
        restore = []
    }

    private func temp() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("robust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    // MARK: - 1. Spaces

    /// Three spaces with three pages each, the middle one in front in each.
    private func makeSpaces() -> (ids: [UUID], tabs: [UUID: Set<Tab.ID>], active: [UUID: Tab.ID]) {
        browser.prefs.usesSpaces = true
        let extra = [Space(id: UUID(), name: "Two", colour: 0, sharesSignIns: true),
                     Space(id: UUID(), name: "Three", colour: 0, sharesSignIns: true)]
        browser.spaces = [Space.first()] + extra
        var tabs: [UUID: Set<Tab.ID>] = [:]
        var active: [UUID: Tab.ID] = [:]
        for space in browser.spaces {
            browser.enter(space.id)
            for word in ["a", "b", "c"] {
                if browser.tabs.last?.isBlank == false { browser.newTab() }
                browser.tabs.last?.restore(url: URL(string: "about:blank#\(space.name)\(word)")!, title: "\(space.name) \(word)")
            }
            browser.select(browser.tabs[browser.tabs.count - 2])
            tabs[space.id] = Set(browser.tabs.map(\.id))
            active[space.id] = browser.activeID
        }
        return (browser.spaces.map(\.id), tabs, active)
    }

    func testRapidSpaceSwitchingNeverLosesOrDuplicatesTabs() {
        let (ids, expected, active) = makeSpaces()
        let everything = expected.values.reduce(into: Set<Tab.ID>()) { $0.formUnion($1) }
        XCTAssertEqual(everything.count, 9)
        var random = SystemRandomNumberGenerator()
        for step in 0..<300 {
            let to = ids.randomElement(using: &random)!
            if step % 7 == 0 { browser.preloadSpaces() }
            if step % 11 == 0 { browser.switchSpace(index: ids.firstIndex(of: to)!) } else { browser.enter(to) }
            XCTAssertEqual(browser.spaceID, to, "step \(step)")
            let here = browser.tabs.map(\.id)
            XCTAssertEqual(Set(here), expected[to], "step \(step): this space's tabs changed")
            XCTAssertEqual(here.count, expected[to]?.count, "step \(step): a tab is in the row twice")
            XCTAssertEqual(browser.activeID, active[to], "step \(step): the space lost its front tab")
            let all = (browser.tabs + browser.parkedTabs).map(\.id)
            XCTAssertEqual(all.count, 9, "step \(step)")
            XCTAssertEqual(Set(all), everything, "step \(step)")
        }
    }

    func testSwitchingToTheSpaceOnScreenChangesNothing() {
        let (ids, expected, active) = makeSpaces()
        browser.enter(ids[1])
        for _ in 0..<5 { browser.enter(ids[1]); browser.switchSpace(to: ids[1]) }
        XCTAssertEqual(Set(browser.tabs.map(\.id)), expected[ids[1]])
        XCTAssertEqual(browser.activeID, active[ids[1]])
        XCTAssertEqual((browser.tabs + browser.parkedTabs).count, 9)
    }

    func testSwitchingToAnUnknownSpaceIsIgnored() {
        let (ids, expected, _) = makeSpaces()
        browser.enter(ids[0])
        browser.enter(UUID())
        XCTAssertEqual(browser.spaceID, ids[0])
        XCTAssertEqual(Set(browser.tabs.map(\.id)), expected[ids[0]])
    }

    // MARK: - 2. Sleep

    /// A page of its own, loaded from a string so no network is needed, and
    /// last looked at long ago.
    private func page(_ url: String, title: String) async throws -> Tab {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = Tab(configuration: configuration)
        tab.setAddressOptimistically(URL(string: url)!)
        tab.web.loadHTMLString("<title>\(title)</title>", baseURL: URL(string: url))
        for _ in 0..<200 where !(tab.title == title && !tab.loading) { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(tab.title, title)
        XCTAssertFalse(tab.loading)
        tab.touch(at: .distantPast)
        return tab
    }

    /// In the row but not in front, its page saying nothing is typed.
    private func background(_ url: String, title: String) async throws -> Tab {
        let tab = try await page(url, title: title)
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        await withCheckedContinuation { continuation in
            tab.web.evaluateInSearch("window.__officeForms = {unsaved: () => false}") { _ in continuation.resume() }
        }
        return tab
    }

    private func front(_ tab: Tab) {
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        browser.select(tab)
    }

    func testSleepingKeepsTheAddressAndTitleAndWakeBringsThemBack() async throws {
        let tab = try await background("https://sleeper.example/path?q=1", title: "Sleeper")
        let said = await withCheckedContinuation { continuation in
            browser.sleep(tab) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(said, "asleep")
        XCTAssertTrue(tab.asleep)
        XCTAssertNil(tab.built, "The page itself is let go")
        XCTAssertEqual(tab.address, URL(string: "https://sleeper.example/path?q=1"))
        XCTAssertEqual(tab.title, "Sleeper")
        XCTAssertTrue(tab.wake(), "There was a page to wake")
        XCTAssertFalse(tab.asleep)
        XCTAssertNotNil(tab.built)
        XCTAssertEqual(tab.address, URL(string: "https://sleeper.example/path?q=1"))
        XCTAssertEqual(tab.title, "Sleeper")
        XCTAssertFalse(tab.wake(), "Nothing left to wake")
    }

    func testWhatMustNeverSleep() async throws {
        let shown = try await page("https://shown.example", title: "Shown")
        front(shown)
        XCTAssertEqual(browser.awake(because: shown), "on screen")

        let loud = try await background("https://loud.example", title: "Loud")
        loud.noisy = true
        XCTAssertEqual(browser.awake(because: loud), "playing sound")

        let pinned = try await background("https://pinned.example", title: "Pinned")
        pinned.pin = "P"
        XCTAssertEqual(browser.awake(because: pinned), "pinned")

        let blank = Tab(configuration: WKWebViewConfiguration())
        XCTAssertEqual(browser.awake(because: blank), "blank")

        let plain = try await background("https://plain.example", title: "Plain")
        XCTAssertNil(browser.awake(because: plain))
        loud.noisy = false
        XCTAssertNil(browser.awake(because: loud), "Quiet again, it may sleep")
    }

    func testTheIdleSweepSleepsOnlyWhatMay() async throws {
        browser.prefs.sleepsTabs = true
        let shown = try await page("https://shown.example", title: "Shown")
        front(shown)
        let loud = try await background("https://loud.example", title: "Loud")
        loud.noisy = true
        let pinned = try await background("https://pinned.example", title: "Pinned")
        pinned.pin = "P"
        let plain = try await background("https://plain.example", title: "Plain")
        let parkedTab = try await page("https://away.example", title: "Away")
        await withCheckedContinuation { continuation in
            parkedTab.web.evaluateInSearch("window.__officeForms = {unsaved: () => false}") { _ in continuation.resume() }
        }
        browser.parked[UUID()] = Parked(tabs: [parkedTab], active: nil)

        browser.sleepIdle(within: 0)
        for _ in 0..<100 where !(plain.asleep && parkedTab.asleep) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(plain.asleep)
        XCTAssertTrue(parkedTab.asleep, "A tab of another space sleeps too")
        XCTAssertFalse(shown.asleep, "The active tab never sleeps")
        XCTAssertFalse(loud.asleep, "A tab playing sound never sleeps")
        XCTAssertFalse(pinned.asleep, "A pin in the space on screen never sleeps")
        XCTAssertEqual(parkedTab.address?.host(), "away.example")
        XCTAssertEqual(parkedTab.title, "Away")
    }

    func testNothingSleepsWithSleepingTurnedOff() async throws {
        browser.prefs.sleepsTabs = false
        let plain = try await background("https://plain.example", title: "Plain")
        browser.sleepIdle(within: 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(plain.asleep)
    }

    // MARK: - 3. Blocker

    private func serve() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let isPage = String(decoding: data ?? Data(), as: UTF8.self).hasPrefix("GET / ")
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
        return try XCTUnwrap(listener.port?.rawValue)
    }

    private func outcome(of webView: WKWebView, port: UInt16) async throws -> String {
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let title = try? await webView.evaluateJavaScript("document.title") as? String, !title.isEmpty {
                return title
            }
        }
        return "timeout"
    }

    func testBundledListsLoad() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore(url: try temp()))
        let shield = Shield()
        await shield.build(store: store)
        XCTAssertNil(shield.trouble)
        XCTAssertEqual(shield.lists.count, 3)
        let controller = WKUserContentController()
        shield.tune(controller, for: "example.com")
        shield.apply(to: [controller])
    }

    func testPausingASiteTakesEffectForThatTabOnly() async throws {
        let port = try serve()
        let folder = try temp()
        for name in ["easylist", "easyprivacy"] {
            let rule = [["trigger": ["url-filter": name == "easylist" ? "ad\\.js" : "track\\.js"],
                         "action": ["type": "block"]]]
            try JSONSerialization.data(withJSONObject: rule, options: .sortedKeys).write(to: folder.appendingPathComponent("\(name).json"))
        }
        let shield = Shield()
        await shield.build(store: try XCTUnwrap(WKContentRuleListStore(url: try temp())), blocklists: folder)
        let kept = Set(Store.settings.stringArray(forKey: "shield.paused") ?? [])
        addTeardownBlock { MainActor.assumeIsolated {
            Store.settings.set(Array(kept).sorted(), forKey: "shield.paused")
        } }

        shield.pause("paused.example", true)
        XCTAssertTrue(shield.isPaused(on: "paused.example"))
        XCTAssertFalse(shield.isPaused(on: "other.example"))

        // Two tabs at once, each told its own site's answer before its page.
        let pausedTab = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let otherTab = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        shield.tune(pausedTab.configuration.userContentController, for: "paused.example")
        shield.tune(otherTab.configuration.userContentController, for: "other.example")
        let paused = try await outcome(of: pausedTab, port: port)
        let other = try await outcome(of: otherTab, port: port)
        XCTAssertEqual(paused, "loaded", "The paused site is let through")
        XCTAssertEqual(other, "blocked", "Another tab is still blocked")

        shield.pause("paused.example", false)
        let again = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        shield.tune(again.configuration.userContentController, for: "paused.example")
        let resumed = try await outcome(of: again, port: port)
        XCTAssertEqual(resumed, "blocked", "Unpausing blocks the next page")
    }

    // MARK: - 4. Private tabs

    func testPrivateTabsLeaveNoHistoryArchiveOrReport() async throws {
        let host = "w13-\(UUID().uuidString.prefix(8).lowercased()).example"
        let url = URL(string: "https://\(host)/secret")!
        addTeardownBlock { MainActor.assumeIsolated { self.browser?.history.forget("\(host)/secret") } }

        // History: a finished private page is not recorded; the same page in
        // an ordinary tab is (so the first check can fail).
        let shy = Tab(shy: true)
        shy.setAddressOptimistically(url)
        browser.prepare(shy)
        browser.insert(shy, at: browser.tabs.count)
        browser.webView(shy.web, didFinish: nil)
        XCTAssertTrue(browser.history.visits(to: [host]).isEmpty, "A private page reached the history")

        let open = Tab()
        open.setAddressOptimistically(url)
        browser.prepare(open)
        browser.insert(open, at: browser.tabs.count)
        browser.webView(open.web, didFinish: nil)
        XCTAssertFalse(browser.history.visits(to: [host]).isEmpty, "An ordinary page is recorded")
        browser.history.forget()
        shy.close()
        open.close()

        // Archive: keep() ignores a private tab and takes an ordinary one.
        let archive = Archive(file: try temp().appendingPathComponent("archive.json"))
        let privateTab = Tab(shy: true)
        privateTab.setAddressOptimistically(url)
        archive.keep(privateTab)
        XCTAssertTrue(archive.entries.isEmpty, "A private tab reached the archive")
        let ordinary = Tab()
        ordinary.setAddressOptimistically(url)
        archive.keep(ordinary)
        XCTAssertEqual(archive.entries.count, 1)

        // Privacy report: a private page's trackers are not counted.
        let report = PrivacyReport(file: nil)
        var seen = Set<String>()
        let trackers: Set<String> = ["tracker.example"]
        let fromPrivate = report.note(hosts: ["tracker.example"], page: "site.example", shy: true,
                                      blocking: true, seen: &seen, trackers: trackers)
        XCTAssertTrue(fromPrivate.isEmpty)
        XCTAssertTrue(seen.isEmpty)
        XCTAssertEqual(report.ledger, PrivacyLedger())
        let fromOrdinary = report.note(hosts: ["tracker.example"], page: "site.example", shy: false,
                                       blocking: true, seen: &seen, trackers: trackers)
        XCTAssertEqual(fromOrdinary, ["tracker.example"])
        XCTAssertNotEqual(report.ledger, PrivacyLedger())
        privateTab.close()
        ordinary.close()
    }

    func testAPrivateTabHasAStoreOfItsOwnThatKeepsNothing() {
        let shy = Tab(shy: true)
        XCTAssertFalse(shy.store.isPersistent)
        XCTAssertFalse(Spaces.everyStore.contains { $0 === shy.store })
        XCTAssertTrue(shy.store !== Store.websites)
        shy.close()
    }

    // MARK: - 5. Deleting a space or profile

    private func pendingErasures() -> Set<String> {
        Set(Store.settings.stringArray(forKey: "spaces.erasing") ?? [])
    }

    func testDeletingASpaceRemovesItsStoreAndNeverFallsBackToTheDefaultOne() async throws {
        let before = pendingErasures()
        addTeardownBlock { MainActor.assumeIsolated { Store.settings.set(before.sorted(), forKey: "spaces.erasing") } }
        let own = Space(id: UUID(), name: "Own", colour: 0, sharesSignIns: false)
        browser.prefs.usesSpaces = true
        browser.spaces.append(own)
        Spaces.write(browser.spaces)
        let store = Spaces.store(for: own.id)
        XCTAssertTrue(store !== Store.websites, "A space with sign-ins of its own has a store of its own")
        XCTAssertTrue(store !== WKWebsiteDataStore.default())
        XCTAssertTrue(store.isPersistent)
        XCTAssertTrue(Spaces.everyStore.contains { $0 === store })

        browser.deleteSpace(own.id)

        XCTAssertFalse(browser.spaces.contains { $0.id == own.id })
        XCTAssertFalse(Spaces.everyStore.contains { $0 === store }, "The deleted space's store is still in use")
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertTrue(pendingErasures().contains(own.id.uuidString) || !identifiers.contains(own.id),
                      "The store is neither gone nor queued for removal")
        // A page of the deleted space asking again is not handed the default store.
        let after = Spaces.store(for: own.id)
        XCTAssertTrue(after !== Store.websites)
        XCTAssertTrue(after !== WKWebsiteDataStore.default())
        Spaces.erase(own.id)
    }

    func testDeletingASpaceThatSharesSignInsLeavesTheSharedStoreAlone() {
        let before = pendingErasures()
        addTeardownBlock { MainActor.assumeIsolated { Store.settings.set(before.sorted(), forKey: "spaces.erasing") } }
        let shared = Space(id: UUID(), name: "Shared", colour: 0, sharesSignIns: true)
        browser.prefs.usesSpaces = true
        browser.spaces.append(shared)
        Spaces.write(browser.spaces)
        let home = Spaces.store(for: Space.firstID)
        XCTAssertTrue(Spaces.store(for: shared.id) === home)
        browser.deleteSpace(shared.id)
        XCTAssertFalse(pendingErasures().contains(shared.id.uuidString), "Its cookies are the profile's: not erased")
        XCTAssertTrue(Spaces.everyStore.contains { $0 === home })
    }

    func testDeletingTheFirstSpaceDoesNothing() {
        let before = pendingErasures()
        Spaces.erase(Space.firstID)
        XCTAssertEqual(pendingErasures(), before)
        browser.deleteSpace(Space.firstID)
        XCTAssertTrue(browser.spaces.contains { $0.id == Space.firstID })
    }

    func testDeletingAProfileRemovesItsStoreAndNeverFallsBackToTheDefaultOne() {
        let before = pendingErasures()
        addTeardownBlock { MainActor.assumeIsolated { Store.settings.set(before.sorted(), forKey: "spaces.erasing") } }
        let profile = Profiles.shared.add(named: "W13 \(UUID().uuidString.prefix(6))")
        let store = Profiles.store(profile.id)
        XCTAssertTrue(store !== Store.websites)
        XCTAssertTrue(Profiles.madeStores.contains { $0 === store })
        XCTAssertTrue(Spaces.everyStore.contains { $0 === store })

        Profiles.shared.delete(profile.id)

        XCTAssertFalse(Profiles.shared.list.contains { $0.id == profile.id })
        XCTAssertFalse(Profiles.madeStores.contains { $0 === store })
        XCTAssertFalse(Spaces.everyStore.contains { $0 === store })
        XCTAssertTrue(pendingErasures().contains(profile.id.uuidString), "Its store must be queued for removal")
        XCTAssertTrue(Spaces.read().allSatisfy { $0.profileID != profile.id })
    }
}
