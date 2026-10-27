import Foundation
import WebKit

// Boosts: a site's own look, kept per site (Arc's Boosts, the way Yab keeps them).
//
// A boost is a name, the sites it is for, and what it changes: a few quick
// switches (a font, a text size, an accent, dark, things to hide), a
// stylesheet, and — only if you wrote it yourself — a script.
//
// Styles go in before the document as Curtain's do, in the same world: they
// are only ever CSS. A script runs in a world of its own that has no message
// handler of Search's in it (never `Web.world`, never the page's), only on the
// sites the boost names, and not in a private tab unless that is switched on
// in Settings. Arc shipped boosts whose scripts came in with a shared link
// and ran with the app's own powers (CVE-2024-45489): here a script is never
// taken from a file without being read and allowed one by one (see
// `Boosts.commitImport`), and what comes in starts off, and is tried on one
// tab before it is kept.

struct Boost: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    /// Hosts it is for, as typed: lower-case, no scheme, no leading www.
    var hosts: [String] = []
    /// Also every subdomain of those hosts.
    var subdomains = true
    var enabled = true
    var css = ""
    // The quick switches.
    var font: String?
    /// Text size as a percentage of the page's.
    var textSize: Int?
    /// `#rrggbb`.
    var accent: String?
    var dark = false
    /// Selectors to take off the page, one rule each.
    var hide: [String] = []
    var js: String?
    /// Came in from a file and has not been kept yet.
    var imported = false
    var date = Date()

    init(name: String = "", hosts: [String] = []) {
        self.name = name
        self.hosts = hosts
    }

    // Every key optional: a file from an older build, or one written by hand.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        hosts = (try? c.decode([String].self, forKey: .hosts)) ?? []
        subdomains = (try? c.decode(Bool.self, forKey: .subdomains)) ?? true
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        css = (try? c.decode(String.self, forKey: .css)) ?? ""
        font = try? c.decode(String.self, forKey: .font)
        textSize = try? c.decode(Int.self, forKey: .textSize)
        accent = try? c.decode(String.self, forKey: .accent)
        dark = (try? c.decode(Bool.self, forKey: .dark)) ?? false
        hide = (try? c.decode([String].self, forKey: .hide)) ?? []
        js = try? c.decode(String.self, forKey: .js)
        imported = (try? c.decode(Bool.self, forKey: .imported)) ?? false
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
    }

    private enum Keys: String, CodingKey {
        case id, name, hosts, subdomains, enabled, css, font, textSize, accent, dark, hide, js, imported, date
    }

    // MARK: - which sites

    /// A host as compared: lower-case, no trailing dot, no leading `www.`.
    static func normal(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespaces).lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// The host itself, or a subdomain of it on a label boundary — never a
    /// substring (`evilexample.com` is not `example.com`) and no wildcards.
    func matches(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let h = Boost.normal(host)
        return hosts.contains { raw in
            let m = Boost.normal(raw)
            return !m.isEmpty && (h == m || subdomains && h.hasSuffix("." + m))
        }
    }

    // MARK: - what it does

    var hasScript: Bool { !(js ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The "what it can do" line.
    var summary: String {
        hasScript ? "Runs scripts on \(hosts.joined(separator: ", "))" : "CSS only"
    }

    /// Why it can't be kept, or nil.
    var problem: String? {
        if hosts.isEmpty || hosts.contains(where: { Boost.normal($0).isEmpty || $0.contains("*") || $0.contains("/") || $0.contains(" ") }) {
            return "Name the site (like example.com)."
        }
        if hosts.count > Boosts.maxHosts { return "At most \(Boosts.maxHosts) sites." }
        if css.utf8.count > Boosts.maxCSS { return "CSS is over 64 KB." }
        if (js ?? "").utf8.count > Boosts.maxJS { return "Script is over 64 KB." }
        if hide.count > Boosts.maxHide { return "At most \(Boosts.maxHide) hidden things." }
        return nil
    }

    // MARK: - the stylesheet

    /// Quick switches and the stylesheet, as one piece of CSS.
    var stylesheet: String {
        var out: [String] = []
        if dark {
            out.append("html { filter: invert(1) hue-rotate(180deg) !important; background: #fff; }")
            out.append("img, picture, video, canvas, svg image, [style*=\"background-image\"] { filter: invert(1) hue-rotate(180deg) !important; }")
        }
        if let font = font?.filter({ $0.isLetter || $0.isNumber || " -.".contains($0) }), !font.isEmpty {
            out.append("html, body, body *:not(code):not(pre):not(kbd):not(samp):not([class*=\"icon\" i]) { font-family: \"\(font)\", system-ui, sans-serif !important; }")
        }
        if let size = textSize, size != 100 {
            out.append("html { font-size: \(min(max(size, 50), 300))% !important; }")
        }
        if let accent, Boost.isHex(accent) {
            out.append(":root { accent-color: \(accent) !important; } a, a:visited { color: \(accent) !important; }")
        }
        for selector in hide where !selector.isEmpty && !selector.contains(where: { "{};<>".contains($0) }) {
            out.append("\(selector) { display: none !important; }")
        }
        if !css.isEmpty { out.append(css) }
        return out.joined(separator: "\n")
    }

    static func isHex(_ text: String) -> Bool {
        text.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }
}

/// One thing to put in a page: where it runs and when.
struct BoostInjection {
    let source: String
    let atStart: Bool
    let world: WKContentWorld
    let isScript: Bool

    var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: atStart ? .atDocumentStart : .atDocumentEnd, forMainFrameOnly: true, in: world)
    }
}

/// A boost read from a file: its script is held apart until allowed.
struct BoostCandidate: Identifiable {
    var boost: Boost
    var script: String?
    var id: UUID { boost.id }
}

@MainActor
final class Boosts: ObservableObject {
    static let shared = Boosts(file: Store.file("boosts.json"))

    nonisolated static let maxCSS = 64 * 1024
    nonisolated static let maxJS = 64 * 1024
    nonisolated static let maxHosts = 10
    nonisolated static let maxHide = 50
    nonisolated static let maxBoosts = 200

    /// Where boost scripts run: nowhere else, and not where Search's own
    /// messages are handled (`Web.world`), nor the page's.
    static let world = WKContentWorld.world(name: "Boosts")

    /// Settings › Pages. Private tabs get no boosts unless this is on.
    static var allowsPrivate: Bool {
        get { Store.settings.bool(forKey: "boosts.private") }
        set { Store.settings.set(newValue, forKey: "boosts.private") }
    }

    @Published private(set) var all: [Boost] = []
    /// Tab → boost being tried on it alone.
    private(set) var trials: [UUID: UUID] = [:]
    private let file: URL?

    init(file: URL?) {
        self.file = file
        if let file { all = Boosts.read(file) }
    }

    // MARK: - injection

    /// What `host` gets in a tab. Nothing in a private tab unless allowed.
    func injections(host: String?, tab: UUID? = nil, shy: Bool, allowsPrivate: Bool? = nil) -> [BoostInjection] {
        guard let host, !shy || (allowsPrivate ?? Boosts.allowsPrivate) else { return [] }
        var out: [BoostInjection] = []
        for boost in all where boost.matches(host) && (boost.enabled || tab.flatMap({ trials[$0] }) == boost.id) {
            let sheet = boost.stylesheet
            if !sheet.isEmpty {
                out.append(BoostInjection(source: Boosts.style(sheet, id: boost.id), atStart: true, world: Web.world, isScript: false))
            }
            if boost.hasScript, let js = boost.js {
                out.append(BoostInjection(source: Boosts.wrap(js), atStart: false, world: Boosts.world, isScript: true))
            }
        }
        return out
    }

    private static func literal(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode([text]), let s = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(s.dropFirst().dropLast())
    }

    static func style(_ css: String, id: UUID) -> String {
        """
        (function () {
          var id = 'wayfinder-boost-\(id.uuidString)';
          var sheet = document.getElementById(id);
          if (!sheet) { sheet = document.createElement('style'); sheet.id = id; (document.head || document.documentElement).appendChild(sheet); }
          sheet.textContent = \(literal(css));
        })();
        """
    }

    static func wrap(_ js: String) -> String {
        "(function () { try {\n\(js)\n} catch (e) { console.error('Boost script failed', e); } })();"
    }

    // MARK: - keeping

    func boost(_ id: UUID) -> Boost? { all.first { $0.id == id } }

    /// The one named for exactly `host`, for the editor.
    func boost(for host: String?) -> Boost? {
        guard let host else { return nil }
        let h = Boost.normal(host)
        return all.first { $0.hosts.map(Boost.normal).contains(h) }
    }

    /// Add or replace. False when it is over a cap or names no site.
    @discardableResult
    func save(_ boost: Boost) -> Bool {
        var boost = boost
        boost.hosts = boost.hosts.map(Boost.normal).filter { !$0.isEmpty }
        guard boost.problem == nil else { return false }
        if let i = all.firstIndex(where: { $0.id == boost.id }) {
            all[i] = boost
        } else {
            guard all.count < Boosts.maxBoosts else { return false }
            all.append(boost)
        }
        write()
        return true
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].enabled = on
        write()
    }

    func remove(_ id: UUID) {
        all.removeAll { $0.id == id }
        trials = trials.filter { $0.value != id }
        write()
    }

    // MARK: - trying

    func tryOn(_ boost: UUID, tab: UUID) { trials[tab] = boost; objectWillChange.send() }
    func endTrial(tab: UUID) { trials[tab] = nil; objectWillChange.send() }

    /// Keep what was tried: it now applies everywhere it is named.
    func keep(_ id: UUID) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].enabled = true
        all[i].imported = false
        trials = trials.filter { $0.value != id }
        write()
    }

    // MARK: - import and export

    private struct Envelope: Codable {
        var version: Int? = 1
        var boosts: [Boost]
    }

    private static func decode(_ data: Data) -> [Boost] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Envelope.self, from: data))?.boosts
            ?? (try? decoder.decode([Boost].self, from: data)) ?? []
    }

    /// Everything, scripts included.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(Envelope(boosts: all))
    }

    /// Boosts read from a file, scripts held apart. Over-cap or siteless
    /// ones are left out. Nothing here is saved or run.
    static func parseImport(_ data: Data) -> [BoostCandidate] {
        decode(data).prefix(maxBoosts).compactMap { original in
            var boost = original
            boost.id = UUID()
            boost.hosts = boost.hosts.map(Boost.normal).filter { !$0.isEmpty }
            guard boost.problem == nil else { return nil }
            let script = boost.hasScript ? boost.js : nil
            boost.js = nil
            boost.enabled = false
            boost.imported = true
            return BoostCandidate(boost: boost, script: script)
        }
    }

    /// Save imported boosts, off. A script goes in only for those whose id is
    /// in `allowing` — the ones whose full source and sites were shown and
    /// agreed to.
    @discardableResult
    func commitImport(_ candidates: [BoostCandidate], allowing: Set<UUID>) -> [Boost] {
        var kept: [Boost] = []
        for var candidate in candidates {
            if allowing.contains(candidate.id) { candidate.boost.js = candidate.script }
            if save(candidate.boost) { kept.append(candidate.boost) }
        }
        return kept
    }

    // MARK: - the file

    private static func read(_ file: URL) -> [Boost] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return decode(data).filter { $0.problem == nil }
    }

    private func write() {
        guard let file else { return }
        let snapshot = all
        Disk.write(file, now: false) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(Envelope(boosts: snapshot))
        }
    }
}
