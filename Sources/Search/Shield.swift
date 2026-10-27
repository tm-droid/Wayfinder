import CryptoKit
import WebKit

// The ad blocker. No settings, no counter, no shield icon going green — it is
// compiled once at launch and then it is simply true that the page is lighter.
//
// A content rule list is enforced inside WebKit's networking, before a request
// is made and before a stylesheet is applied, so this costs nothing at run time
// in the way a JavaScript blocker does.

@MainActor
final class Shield: ObservableObject {
    static let shared = Shield()

    /// Search's own list, then EasyList and EasyPrivacy (see Blocklists/).
    /// Each is under WebKit's 150,000-rule cap, so none needs splitting.
    private(set) var lists: [WKContentRuleList] = []
    /// How many of the last compile's lists came from the store, not WebKit.
    private(set) var reused = 0
    private var waiting: [WKUserContentController] = []

    /// Set the one time compiling the list didn't work. The toggle in
    /// Settings can say "on" all it wants; nothing is actually blocked until
    /// this is nil, so it is the one thing worth telling a person about
    /// rather than failing the quiet way a missing ad is quiet.
    @Published private(set) var trouble: String?

    /// On unless somebody said otherwise. Every tab's controller is told when
    /// this changes, so it takes effect on the next request rather than the
    /// next launch.
    var enabled = true

    /// Sites it is off for — the ones it broke. A checkout that never
    /// finishes, a video that never starts: switching off here, for this site,
    /// beats switching off everywhere and forgetting to switch back.
    private(set) var paused: Set<String> = Set(
        Store.settings.stringArray(forKey: "shield.paused") ?? []
    )

    func isPaused(on host: String?) -> Bool {
        guard let host else { return false }
        return paused.contains(host)
    }

    func pause(_ host: String, _ off: Bool) {
        if off { paused.insert(host) } else { paused.remove(host) }
        Store.settings.set(Array(paused).sorted(), forKey: "shield.paused")
    }

    /// Before each page: the lists go on or off for the site this tab is
    /// heading to. A rule list is enforced from the moment it is added, so
    /// doing this at the navigation is what makes "off for this site" true
    /// for the whole page rather than for the second half of it. It is also
    /// the allowlist: `ignore-previous-rules` only reaches rules in its own
    /// list, so a site is let through by not adding any list at all.
    func tune(_ controller: WKUserContentController, for host: String?) {
        lists.forEach(controller.remove)
        if enabled, !isPaused(on: host) { lists.forEach(controller.add) }
    }

    /// Where EasyList and EasyPrivacy ship: the app's Resources, or the
    /// source tree when run from `swift test`.
    static let blocklists: URL? = {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Blocklists")
        return [Bundle.main.resourceURL?.appendingPathComponent("Blocklists"), source]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("easylist.json").path) }
    }()

    /// Third parties whose only job is to watch or to sell. First-party
    /// requests are untouched: a site's own scripts are the site.
    private static let unwanted = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "googletagservices.com", "google-analytics.com", "googletagmanager.com",
        "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net",
        "33across.com", "teads.tv", "moatads.com", "adroll.com",
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms",
        "mixpanel.com", "amplitude.com", "segment.com", "segment.io",
        "branch.io", "appsflyer.com", "adjust.com", "analytics.tiktok.com",
        "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
    ]

    /// The few slots that are reliably an advertisement and nothing else. Kept
    /// deliberately short — a generous cosmetic list is how a blocker starts
    /// eating the page it was meant to clean.
    ///
    /// The second half are the boxes a site keeps open for the ad while it
    /// loads: with the ad blocked they stay, empty, a banner's height of
    /// nothing (#159). Each is a whole class name from EasyList's generic
    /// hiding list, matched as a whole word: an element whose class is
    /// `ad-slot` goes, one whose class merely contains "ad" stays.
    private static let slots = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]",
        "[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]", "#taboola-below-article",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
        "iframe[src*=\"amazon-adsystem\"]",
        ".ad-slot", ".ad-slot-container", ".top-banner-ad-container",
        ".ad-leaderboard", ".ad-billboard", ".ad-giga", ".ad-mpu", ".ad-mrec",
        ".ad-unit", ".adunit", ".adslot", ".dfp-ad", ".gpt-ad", ".w_ad",
    ]

    /// Slots with names too plain, or too much a site's own, to hide
    /// everywhere — AS and El País call theirs just `.ad` — hidden only on
    /// the sites EasyList's own site rules hide them on.
    private static let slotsBySite: [(sites: [String], selector: String)] = [
        (["*as.com", "*elpais.com"], ".ad"),
        (["*theguardian.com"], ".top-fronts-banner-ad-container"),
        (["*independent.co.uk", "*the-independent.com"], "#billboard-wrapper"),
        (["*cnn.com"], ".ad-slot-header__wrapper"),
    ]

    static func networkFilter(for domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        // WebKit's canonical HTTP URLs end the host with a port or a slash.
        return "^https?://([^/]+\\.)?\(escaped)[:/]"
    }

    func compile() {
        guard lists.isEmpty else { return }
        Task { await build() }
    }

    /// Compiles each list, or takes it from the store: the store's name for
    /// a list carries a hash of its text, so a launch recompiles only what
    /// changed, and what no longer matches is deleted.
    func build(store: WKContentRuleListStore? = .default(), blocklists: URL? = Shield.blocklists) async {
        trouble = nil
        reused = 0
        guard let store else {
            trouble = "WebKit has nowhere to compile it"
            return
        }
        guard let own = ownRules() else {
            trouble = "Couldn't build the block list"
            return
        }
        // Reading and hashing 16 MB is not for the main thread.
        let sources: [(id: String, data: Data)] = await Task.detached {
            var found = [("office-shield", own)]
            for name in ["easylist", "easyprivacy"] {
                if let folder = blocklists,
                   let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")) {
                    found.append((name, data))
                }
            }
            return found.map { name, data in
                let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
                return ("\(name).\(hash)", data)
            }
        }.value

        var compiled: [WKContentRuleList] = []
        for source in sources {
            if let hit = try? await store.contentRuleList(forIdentifier: source.id) {
                compiled.append(hit)
                reused += 1
            } else if let made = try? await store.compileContentRuleList(
                forIdentifier: source.id, encodedContentRuleList: String(decoding: source.data, as: UTF8.self)
            ) {
                compiled.append(made)
            } else {
                trouble = "Compiling the block list failed"
            }
        }
        if compiled.count < 3, trouble == nil { trouble = "A block list is missing" }
        let wanted = Set(sources.map(\.id))
        for stale in await store.availableIdentifiers() ?? [] where !wanted.contains(stale) {
            try? await store.removeContentRuleList(forIdentifier: stale)
        }
        lists = compiled
        // Tabs that opened while this was still compiling get it now.
        if enabled { waiting.forEach { c in compiled.forEach(c.add) } }
        waiting = []
    }

    private func ownRules() -> Data? {
        var rules: [[String: Any]] = Shield.unwanted.map { domain in
            return [
                "trigger": [
                    "url-filter": Shield.networkFilter(for: domain),
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": Shield.slots.joined(separator: ", ")],
        ])
        // YouTube's ad reports and ad paths (see YouTubeAds.swift).
        rules += YouTubeAds.rules
        rules += Shield.slotsBySite.map { entry in
            [
                "trigger": ["url-filter": ".*", "if-domain": entry.sites],
                "action": ["type": "css-display-none", "selector": entry.selector],
            ]
        }
        return try? JSONSerialization.data(withJSONObject: rules, options: .sortedKeys)
    }

    /// Every tab asks for it; whoever asks before it is ready is remembered.
    func protect(_ controller: WKUserContentController) {
        if !lists.isEmpty {
            if enabled { lists.forEach(controller.add) }
        } else {
            waiting.append(controller)
        }
    }

    /// Switched on or off for every page that is already open.
    func apply(to controllers: [WKUserContentController]) {
        for controller in controllers {
            lists.forEach(controller.remove)
            if enabled { lists.forEach(controller.add) }
        }
    }
}
