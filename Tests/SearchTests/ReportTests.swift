import XCTest
@testable import Search

@MainActor
final class ReportTests: XCTestCase {
    func testExtractsWholeHostRulesOnly() throws {
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": "^[^:]+:(//)?([^/]+\\.)?tracker\\.example\\.com[/:?#]"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^https?://([^/]+\\.)?doubleclick\\.net[:/]"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^http://a\\.pr-cy\\.ru"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^[^:]+:(//)?([^/]+\\.)?awin1\\.com/cawshow\\.php"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "/aclib\\.js"], "action": ["type": "block"]],
            ["trigger": ["url-filter": "^[^:]+:(//)?([^/]+\\.)?allowed\\.com[/:?#]"], "action": ["type": "ignore-previous-rules"]],
            ["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": ".ad"]],
        ]
        let found = TrackerDomains.extract(from: try JSONSerialization.data(withJSONObject: rules))
        XCTAssertEqual(found, ["tracker.example.com", "doubleclick.net", "a.pr-cy.ru"])
    }

    func testMatchesSubdomainsNotSubstrings() {
        let set: Set<String> = ["example.com", "t.co"]
        XCTAssertEqual(TrackerDomains.match("example.com", in: set), "example.com")
        XCTAssertEqual(TrackerDomains.match("A.B.Example.com", in: set), "example.com")
        XCTAssertNil(TrackerDomains.match("notexample.com", in: set))
        XCTAssertNil(TrackerDomains.match("example.com.evil.org", in: set))
        XCTAssertNil(TrackerDomains.match("com", in: set))
        XCTAssertEqual(TrackerDomains.match("x.t.co", in: set), "t.co")
    }

    func testBundledListsYieldDomains() throws {
        let folder = try XCTUnwrap(Shield.blocklists)
        let data = try Data(contentsOf: folder.appendingPathComponent("easyprivacy.json"))
        let found = TrackerDomains.extract(from: data)
        XCTAssertGreaterThan(found.count, 1000)
        XCTAssertTrue(found.allSatisfy { $0.contains(".") })
    }

    func testPayloadValidation() {
        let long = String(repeating: "a", count: 300) + ".com"
        let many = (0..<80).map { "h\($0).example.com" }
        XCTAssertEqual(ReportPayload.hosts(from: ["hosts": ["Ads.Example.com", "bad host.com", "x:80.com", "localhost", long, 5]]),
                       ["ads.example.com"])
        XCTAssertEqual(ReportPayload.hosts(from: ["hosts": many]).count, ReportPayload.perMessage)
        XCTAssertTrue(ReportPayload.hosts(from: "nope").isEmpty)
        XCTAssertTrue(ReportPayload.hosts(from: ["hosts": "a.com"]).isEmpty)
        XCTAssertTrue(ReportPayload.hosts(from: ["other": ["a.com"]]).isEmpty)
    }

    func testDedupesPerPageAndCountsPreventedOrSeen() {
        let report = PrivacyReport(file: nil)
        var seen = Set<String>()
        let trackers: Set<String> = ["adtech.com", "pixel.io"]
        let now = Date()
        let hosts = ["a.adtech.com", "b.adtech.com", "pixel.io", "news.example.org", "cdn.page.com"]
        let fresh = report.note(hosts: hosts, page: "www.page.com", shy: false, blocking: true,
                                seen: &seen, trackers: trackers, now: now)
        XCTAssertEqual(fresh, ["adtech.com", "pixel.io"])
        XCTAssertTrue(report.note(hosts: hosts, page: "www.page.com", shy: false, blocking: true,
                                  seen: &seen, trackers: trackers, now: now).isEmpty)
        var other = Set<String>()
        report.note(hosts: ["adtech.com"], page: "www.page.com", shy: false, blocking: false,
                    seen: &other, trackers: trackers, now: now)
        let s = report.ledger.summary(days: 7, now: now)
        XCTAssertEqual(s.prevented, 2)
        XCTAssertEqual(s.seen, 1)
        XCTAssertEqual(s.trackers.first?.name, "adtech.com")
        XCTAssertEqual(s.sites.first?.name, "page.com")
    }

    func testScriptRunsInSubFrames() {
        XCTAssertFalse(ReportRelay.userScript.isForMainFrameOnly)
    }

    func testSubFrameTrackersCountOnceForTheTopLevelSite() {
        let report = PrivacyReport(file: nil)
        var seen = Set<String>()
        let trackers: Set<String> = ["adtech.com", "pixel.io"]
        let now = Date()
        // Main frame, then an iframe on another origin that loads one the
        // page already loaded and one of its own; the page is the top-level site.
        report.note(hosts: ["a.adtech.com"], page: "www.page.com", shy: false, blocking: true,
                    seen: &seen, trackers: trackers, now: now)
        let fresh = report.note(hosts: ["b.adtech.com", "pixel.io", "frame.other.org"], page: "www.page.com",
                                shy: false, blocking: true, seen: &seen, trackers: trackers, now: now)
        XCTAssertEqual(fresh, ["pixel.io"])
        let s = report.ledger.summary(days: 7, now: now)
        XCTAssertEqual(s.prevented, 2)
        XCTAssertEqual(s.sites.map(\.name), ["page.com"])
    }

    func testFirstPartyIsNotATracker() {
        let report = PrivacyReport(file: nil)
        var seen = Set<String>()
        report.note(hosts: ["metrics.google.com"], page: "www.google.com", shy: false, blocking: true,
                    seen: &seen, trackers: ["google.com"])
        XCTAssertEqual(report.ledger.summary(days: 7, now: Date()).total, 0)
    }

    func testShyTabsAreNeverRecorded() {
        let report = PrivacyReport(file: nil)
        var seen = Set<String>()
        let fresh = report.note(hosts: ["adtech.com"], page: "page.com", shy: true, blocking: true,
                                seen: &seen, trackers: ["adtech.com"])
        XCTAssertTrue(fresh.isEmpty)
        XCTAssertTrue(seen.isEmpty)
        XCTAssertTrue(report.ledger.days.isEmpty)
    }

    func testRetentionAndWindows() throws {
        var ledger = PrivacyLedger()
        let now = Date()
        let day = { (back: Int) in try! XCTUnwrap(Calendar.current.date(byAdding: .day, value: -back, to: now)) }
        ledger.record(tracker: "a.com", site: "s.com", prevented: true, on: day(40))
        ledger.record(tracker: "a.com", site: "s.com", prevented: true, on: day(20))
        ledger.record(tracker: "b.com", site: "t.com", prevented: false, on: day(3))
        ledger.record(tracker: "b.com", site: "t.com", prevented: true, on: now)
        XCTAssertEqual(ledger.days.count, 3, "40 days old is gone")
        XCTAssertEqual(ledger.summary(days: 7, now: now).total, 2)
        XCTAssertEqual(ledger.summary(days: 30, now: now).total, 3)
        XCTAssertEqual(ledger.summary(days: 30, now: now).trackers.first?.name, "b.com")
        // 25 days on, the 20-day-old entry has aged out of the 30.
        ledger.prune(now: day(-25))
        XCTAssertEqual(ledger.days.count, 2)
        ledger.prune(now: day(-31))
        XCTAssertEqual(ledger.days.count, 0)
    }

    func testClearAndRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var ledger = PrivacyLedger()
        ledger.record(tracker: "a.com", site: "s.com", prevented: true, on: Date())
        try JSONEncoder().encode(ledger).write(to: file)
        let report = PrivacyReport(file: file)
        XCTAssertEqual(report.ledger, ledger)
        report.clear()
        XCTAssertTrue(report.ledger.days.isEmpty)
    }
}
