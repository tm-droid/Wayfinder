import SwiftUI
import WebKit

// An estimated privacy report, in the manner of Safari's.
//
// WebKit has no public count of what a content rule list blocked, so this
// does not count blocks. A script in the page lists the third-party hosts it
// tried to reach (resource timing for what loaded, `error` events for what
// didn't); the hosts that are on the blocklists' own tracker domains are
// counted once per page. With Shield on for the site that is "prevented",
// otherwise "seen". An estimate, and labelled one.
//
// A private tab is never recorded: no script is added to it, and its relay
// drops whatever arrives all the same.

/// The domains the bundled lists block outright, read out of their rules.
enum TrackerDomains {
    /// How a rule's `url-filter` begins when it names a host: any scheme, or
    /// http(s) alone, then an optional subdomain wildcard.
    private static let anchors = [
        "^[^:]+:(//)?([^/]+\\.)?", "^[^:]+://+([^:/]+\\.)?", "^https?://([^/]+\\.)?",
        "^https://", "^http://",
    ]
    /// What may follow the domain for the rule to be about the whole host,
    /// not one path on it.
    private static let ends = ["", "[/:?#]", "[:/]", "[^a-z0-9_.%-]"]

    /// "example.com" for `^[^:]+:(//)?([^/]+\.)?example\.com[/:?#]`; nil for a
    /// rule about a path, a keyword or anything else.
    static func domain(in filter: String) -> String? {
        guard let anchor = anchors.first(where: filter.hasPrefix) else { return nil }
        var rest = filter.dropFirst(anchor.count)
        var name = ""
        while let c = rest.first {
            if c == "\\" {
                rest = rest.dropFirst()
                guard rest.first == "." else { return nil }
                name.append(".")
            } else if c.isASCII, c.isLowercase || c.isNumber || c == "-" {
                name.append(c)
            } else {
                break
            }
            rest = rest.dropFirst()
        }
        guard ends.contains(String(rest)), name.contains("."), !name.hasPrefix("."), !name.hasSuffix("."),
              !name.contains("..") else { return nil }
        return name
    }

    /// Every host a rule list blocks outright (`block` rules only).
    static func extract(from rules: Data) -> Set<String> {
        guard let list = try? JSONSerialization.jsonObject(with: rules) as? [[String: Any]] else { return [] }
        var found = Set<String>()
        for rule in list {
            guard (rule["action"] as? [String: Any])?["type"] as? String == "block",
                  let filter = (rule["trigger"] as? [String: Any])?["url-filter"] as? String,
                  let name = domain(in: filter) else { continue }
            found.insert(name)
        }
        return found
    }

    /// The listed domain a host is, or sits under: "a.b.example.com" matches
    /// "example.com"; "notexample.com" does not.
    static func match(_ host: String, in domains: Set<String>) -> String? {
        var name = Substring(host.lowercased())
        while name.contains(".") {
            if domains.contains(String(name)) { return String(name) }
            name = name.drop { $0 != "." }.dropFirst()
        }
        return nil
    }

    @MainActor private static var loaded: Set<String>?
    @MainActor private static var loading = false

    /// Search's own list plus EasyList and EasyPrivacy, read once in the
    /// background. Empty until it has been (a report is an estimate).
    @MainActor static var all: Set<String> {
        if let loaded { return loaded }
        if !loading {
            loading = true
            let folder = Shield.blocklists, own = Shield.unwanted
            Task.detached {
                var all = Set(own)
                for name in ["easylist", "easyprivacy"] {
                    if let data = try? Data(contentsOf: (folder ?? URL(fileURLWithPath: "/")).appendingPathComponent("\(name).json")) {
                        all.formUnion(extract(from: data))
                    }
                }
                let found = all
                await MainActor.run { loaded = found }
            }
        }
        return []
    }
}

/// What a page may tell native code: a short list of plain host names.
enum ReportPayload {
    static let perMessage = 50
    static let perPage = 500

    static func hosts(from body: Any) -> [String] {
        guard let list = (body as? [String: Any])?["hosts"] as? [Any] else { return [] }
        return list.prefix(perMessage).compactMap { item in
            guard let host = (item as? String)?.lowercased(), host.count <= 253, host.contains("."),
                  host.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == ".") })
            else { return nil }
            return host
        }
    }
}

/// Per day, per site, per tracker domain.
struct PrivacyLedger: Codable, Equatable {
    struct Tally: Codable, Equatable {
        var prevented = 0
        var seen = 0
        var total: Int { prevented + seen }
    }

    struct Summary {
        var prevented = 0
        var seen = 0
        var trackers: [(name: String, count: Int)] = []
        var sites: [(name: String, count: Int)] = []
        var total: Int { prevented + seen }
    }

    static let keptDays = 30

    var days: [String: [String: [String: Tally]]] = [:]

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func first(_ span: Int, now: Date) -> String {
        key(Calendar.current.date(byAdding: .day, value: 1 - span, to: now) ?? now)
    }

    mutating func record(tracker: String, site: String, prevented: Bool, on date: Date) {
        let day = Self.key(date)
        if prevented { days[day, default: [:]][site, default: [:]][tracker, default: Tally()].prevented += 1 }
        else { days[day, default: [:]][site, default: [:]][tracker, default: Tally()].seen += 1 }
        prune(now: date)
    }

    /// Drops every day before the last 30, today included.
    mutating func prune(now: Date) {
        let oldest = Self.first(Self.keptDays, now: now)
        days = days.filter { $0.key >= oldest }
    }

    func summary(days span: Int, now: Date, top: Int = 10) -> Summary {
        let oldest = Self.first(span, now: now)
        var out = Summary()
        var byTracker: [String: Int] = [:], bySite: [String: Int] = [:]
        for (day, sites) in days where day >= oldest {
            for (site, trackers) in sites {
                for (tracker, tally) in trackers {
                    out.prevented += tally.prevented
                    out.seen += tally.seen
                    byTracker[tracker, default: 0] += tally.total
                    bySite[site, default: 0] += tally.total
                }
            }
        }
        func ranked(_ d: [String: Int]) -> [(name: String, count: Int)] {
            d.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(top).map { ($0.key, $0.value) }
        }
        out.trackers = ranked(byTracker)
        out.sites = ranked(bySite)
        return out
    }
}

@MainActor
final class PrivacyReport: ObservableObject {
    /// A profile's file: Personal's is privacy-report.json, as ever.
    nonisolated static func fileName(for profile: UUID) -> String {
        profile == Profile.personalID ? "privacy-report.json" : "privacy-report-\(profile.uuidString).json"
    }

    @Published private(set) var ledger = PrivacyLedger()
    private var saving = false
    private var retired = false
    private let file: URL?

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode(PrivacyLedger.self, from: data) {
            ledger = stored
            ledger.prune(now: Date())
        }
    }

    /// One page's hosts, from its relay. `seen`: the tracker domains already
    /// counted on this page. Returns the ones new here, prevented or not.
    @discardableResult
    func note(
        hosts: [String], page: String, shy: Bool, blocking: Bool, seen: inout Set<String>,
        trackers given: Set<String>? = nil, now: Date = Date()
    ) -> [String] {
        let trackers = given ?? TrackerDomains.all
        guard !shy, !trackers.isEmpty else { return [] }
        let site = Vault.registrable(page)
        var fresh: [String] = []
        for host in hosts {
            guard seen.count < ReportPayload.perPage, host != page, Vault.registrable(host) != site,
                  let tracker = TrackerDomains.match(host, in: trackers), seen.insert(tracker).inserted
            else { continue }
            ledger.record(tracker: tracker, site: site, prevented: blocking, on: now)
            fresh.append(tracker)
        }
        if !fresh.isEmpty { save() }
        return fresh
    }

    func clear() {
        ledger = PrivacyLedger()
        save()
    }

    /// Its profile deleted: emptied, its file removed, and nothing written again.
    func retire() {
        retired = true
        ledger = PrivacyLedger()
        if let file { Disk.remove(file) }
    }

    private func save() {
        guard let file, !saving else { return }
        saving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            saving = false
            guard !retired else { return }
            let snapshot = ledger
            Disk.write(file) { try? JSONEncoder().encode(snapshot) }
        }
    }
}

/// Carries a page's third-party hosts to the report.
final class ReportRelay: NSObject, WKScriptMessageHandler {
    static let name = "officeReport"

    weak var tab: Tab?
    /// The report of the profile the tab's window is in (Browser.prepare).
    var report: PrivacyReport?
    /// The tracker domains Shield was on for, counted on the page now; a new
    /// document starts again.
    private(set) var prevented: [String] = []
    private var seen = Set<String>()

    func reset() {
        prevented = []
        seen = []
    }

    static let script = """
    (function () {
      if (window.__officeReport) return;
      window.__officeReport = true;
      var seen = {}, count = 0, queue = [], timer = 0;
      function flush() {
        timer = 0;
        var batch = queue.splice(0, 50);
        if (batch.length) window.webkit.messageHandlers.officeReport.postMessage({ hosts: batch });
        if (queue.length) timer = setTimeout(flush, 1500);
      }
      function note(url) {
        try {
          var u = new URL(url, location.href);
          if (u.protocol !== 'http:' && u.protocol !== 'https:') return;
          var h = u.hostname.toLowerCase();
          if (!h || h === location.hostname || seen[h] || count >= 500) return;
          seen[h] = 1; count++; queue.push(h);
          if (!timer) timer = setTimeout(flush, 1500);
        } catch (_) {}
      }
      try {
        new PerformanceObserver(function (list) {
          list.getEntries().forEach(function (e) { note(e.name); });
        }).observe({ type: 'resource', buffered: true });
      } catch (_) {}
      // What was refused never reaches resource timing, but its element hears.
      window.addEventListener('error', function (e) {
        var t = e.target;
        if (t && t !== window) note(t.currentSrc || t.src || t.href);
      }, true);
    })();
    """

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.world == Web.world else { return }
        let hosts = ReportPayload.hosts(from: message.body)
        MainActor.assumeIsolated {
            guard let tab, !tab.shy, let url = tab.pageAddress,
                  ["http", "https"].contains(url.scheme?.lowercased()), let page = url.host() else { return }
            let blocking = Shield.shared.enabled && !Shield.shared.isPaused(on: page)
            guard let report else { return }
            let fresh = report.note(
                hosts: hosts, page: page, shy: tab.shy, blocking: blocking, seen: &seen
            )
            if blocking { prevented += fresh }
        }
    }
}

// MARK: - Settings

/// Settings › Privacy › Privacy report: the last 7 or 30 days.
struct PrivacyReportView: View {
    @ObservedObject var report: PrivacyReport
    @State private var span = 7

    var body: some View {
        let s = report.ledger.summary(days: span, now: Date())
        Rule()
        Line("\(s.prevented) trackers prevented (estimated)", "Plus \(s.seen) seen where blocking was off") {
            Picker("", selection: $span) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 140)
        }
        if !s.trackers.isEmpty {
            Rule()
            Line("Top trackers", s.trackers.prefix(5).map { "\($0.name) \($0.count)" }.joined(separator: ", ")) { EmptyView() }
            Rule()
            Line("Top sites", s.sites.prefix(5).map { "\($0.name) \($0.count)" }.joined(separator: ", ")) { EmptyView() }
        }
    }
}
