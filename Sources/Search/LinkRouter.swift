import Foundation

// Link routing, as Arc's Air Traffic Control has it: a link from another app
// (the Mac's default-browser handoff, see Links.take) goes where the user's
// rules say — "github.com → Space Work", "zoom.us → Little window".
//
// This file is the logic and the file on disk, nothing that touches a
// window, so it can be tested alone. The rules are one list per profile,
// first match wins, in the user's order.

/// Where a rule sends a link.
enum LinkTarget: Hashable, Codable {
    case space(UUID)
    case little
    case current

    private var text: String {
        switch self {
        case .space(let id): return "space:" + id.uuidString
        case .little: return "little"
        case .current: return "current"
        }
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        if text == "little" { self = .little }
        else if text == "current" { self = .current }
        else if text.hasPrefix("space:"), let id = UUID(uuidString: String(text.dropFirst(6))) { self = .space(id) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

struct LinkRule: Equatable, Codable, Identifiable {
    var id = UUID()
    /// An exact host ("github.com"), or "*.github.com" for any subdomain of
    /// it — not the bare domain itself, and never a longer name that merely
    /// ends the same ("evilgithub.com").
    var pattern: String
    var target: LinkTarget
}

/// Where a link goes once the rules have been read.
enum LinkDestination: Equatable {
    case space(UUID)
    case little
    case current
}

enum LinkRouter {
    /// A host as the rules compare it: lowercase, in punycode, no port,
    /// no trailing dot. Nil for text that is not a host.
    static func normalize(host text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        // A pattern may be pasted as an address, or with a port.
        let address = host.contains("://") ? host : "https://" + host
        guard let parsed = URL(string: address)?.host else { return nil }
        host = parsed
        while host.hasSuffix(".") { host.removeLast() }
        host = host.lowercased()
        return host.isEmpty || host.contains("*") ? nil : host
    }

    /// Whether a rule's pattern covers a host (both in any spelling).
    static func matches(pattern: String, host: String) -> Bool {
        guard let host = normalize(host: host) else { return false }
        let text = pattern.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("*.") {
            guard let base = normalize(host: String(text.dropFirst(2))) else { return false }
            return host.hasSuffix("." + base)
        }
        guard let exact = normalize(host: text) else { return false }
        return host == exact
    }

    /// The first rule that covers the link, as a destination; nil when none
    /// does and the link goes where links go without rules. A rule pointing
    /// at a space that is gone sends the link to the current space.
    static func route(_ url: URL, rules: [LinkRule], spaceExists: (UUID) -> Bool) -> LinkDestination? {
        guard !url.isFileURL, let host = url.host else { return nil }
        guard let rule = rules.first(where: { matches(pattern: $0.pattern, host: host) }) else { return nil }
        switch rule.target {
        case .space(let id): return spaceExists(id) ? .space(id) : .current
        case .little: return .little
        case .current: return .current
        }
    }
}

/// One profile's rules on disk.
enum LinkRules {
    static func file(profile: UUID, in folder: URL = Store.folder) -> URL {
        folder.appendingPathComponent("link-rules-\(profile.uuidString).json")
    }

    /// Empty when there is no file, and when there is one that doesn't read.
    static func read(profile: UUID, in folder: URL = Store.folder) -> [LinkRule] {
        guard let data = try? Data(contentsOf: file(profile: profile, in: folder)),
              let rules = try? JSONDecoder().decode([LinkRule].self, from: data)
        else { return [] }
        return rules
    }

    static func write(_ rules: [LinkRule], profile: UUID, in folder: URL = Store.folder) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(profile: profile, in: folder), options: .atomic)
    }
}
