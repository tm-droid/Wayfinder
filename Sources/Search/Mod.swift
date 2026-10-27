import Foundation

// Mods: small declarative changes to the browser's look, like Zen's. A mod is
// data, never code: a name, an optional partial look (SpaceLook.swift), a few
// switches from a closed list. There is no field that runs anything, and no
// CSS (the browser's own pages are native). A manifest with a key or flag
// this version does not know is refused rather than half-applied, so a mod
// cannot ask for more than it is shown to do.

/// The switches a mod can set; `ModFlags` holds their values.
enum ModFlag: String, Codable, CaseIterable {
    case hoverOnlyClose, biggerMute, dimUnloadedTabs, tabTextSize, sleekBorder
    case compactFindBar, hidePinnedReset, resetOnHoverOnly
}

/// A mod's switches. Each is nil for "not mentioned", so mods layer.
struct ModFlags: Codable, Equatable {
    var hoverOnlyClose: Bool?
    var biggerMute: Bool?
    /// How far unloaded tabs fade, 0…1.
    var dimUnloadedTabs: Double?
    /// Points.
    var tabTextSize: Double?
    var sleekBorder: Bool?
    var compactFindBar: Bool?
    var hidePinnedReset: Bool?
    var resetOnHoverOnly: Bool?

    static let dimRange = 0.0...1.0
    static let tabTextSizeRange = SpaceLook.tabTextSizeRange

    init(hoverOnlyClose: Bool? = nil, biggerMute: Bool? = nil, dimUnloadedTabs: Double? = nil, tabTextSize: Double? = nil,
         sleekBorder: Bool? = nil, compactFindBar: Bool? = nil, hidePinnedReset: Bool? = nil, resetOnHoverOnly: Bool? = nil) {
        self.hoverOnlyClose = hoverOnlyClose
        self.biggerMute = biggerMute
        self.dimUnloadedTabs = dimUnloadedTabs
        self.tabTextSize = tabTextSize
        self.sleekBorder = sleekBorder
        self.compactFindBar = compactFindBar
        self.hidePinnedReset = hidePinnedReset
        self.resetOnHoverOnly = resetOnHoverOnly
    }

    /// Strict: a key that is not a `ModFlag`, or a value of the wrong type, throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ModKey.self)
        for key in c.allKeys where ModFlag(rawValue: key.stringValue) == nil {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "unknown flag \(key.stringValue)")
        }
        func get<T: Decodable>(_ flag: ModFlag) throws -> T? { try c.decodeIfPresent(T.self, forKey: ModKey(flag.rawValue)) }
        hoverOnlyClose = try get(.hoverOnlyClose)
        biggerMute = try get(.biggerMute)
        dimUnloadedTabs = try get(.dimUnloadedTabs)
        tabTextSize = try get(.tabTextSize)
        sleekBorder = try get(.sleekBorder)
        compactFindBar = try get(.compactFindBar)
        hidePinnedReset = try get(.hidePinnedReset)
        resetOnHoverOnly = try get(.resetOnHoverOnly)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ModKey.self)
        try c.encodeIfPresent(hoverOnlyClose, forKey: ModKey(ModFlag.hoverOnlyClose.rawValue))
        try c.encodeIfPresent(biggerMute, forKey: ModKey(ModFlag.biggerMute.rawValue))
        try c.encodeIfPresent(dimUnloadedTabs, forKey: ModKey(ModFlag.dimUnloadedTabs.rawValue))
        try c.encodeIfPresent(tabTextSize, forKey: ModKey(ModFlag.tabTextSize.rawValue))
        try c.encodeIfPresent(sleekBorder, forKey: ModKey(ModFlag.sleekBorder.rawValue))
        try c.encodeIfPresent(compactFindBar, forKey: ModKey(ModFlag.compactFindBar.rawValue))
        try c.encodeIfPresent(hidePinnedReset, forKey: ModKey(ModFlag.hidePinnedReset.rawValue))
        try c.encodeIfPresent(resetOnHoverOnly, forKey: ModKey(ModFlag.resetOnHoverOnly.rawValue))
    }

    /// Fields `other` sets replace this one's; the rest stay.
    func merged(with other: ModFlags) -> ModFlags {
        ModFlags(hoverOnlyClose: other.hoverOnlyClose ?? hoverOnlyClose,
                 biggerMute: other.biggerMute ?? biggerMute,
                 dimUnloadedTabs: other.dimUnloadedTabs ?? dimUnloadedTabs,
                 tabTextSize: other.tabTextSize ?? tabTextSize,
                 sleekBorder: other.sleekBorder ?? sleekBorder,
                 compactFindBar: other.compactFindBar ?? compactFindBar,
                 hidePinnedReset: other.hidePinnedReset ?? hidePinnedReset,
                 resetOnHoverOnly: other.resetOnHoverOnly ?? resetOnHoverOnly)
    }

    /// The flags of `mods` in order, later winning.
    static func merge(_ mods: [Mod]) -> ModFlags {
        mods.reduce(ModFlags()) { $0.merged(with: $1.flags ?? ModFlags()) }
    }
}

enum ModError: Error, Equatable {
    case badID
    case emptyName
    case nameTooLong
    case authorTooLong
    case badVersion
    case flagOutOfRange(ModFlag)
}

struct Mod: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var author: String
    /// "1", "1.2" or "1.2.3".
    var version: String
    var look: SpaceLook?
    var flags: ModFlags?

    static let maxNameLength = 60
    static let maxAuthorLength = 80

    init(id: String, name: String, author: String = "", version: String = "1.0.0",
         look: SpaceLook? = nil, flags: ModFlags? = nil) {
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.look = look
        self.flags = flags
    }

    /// Strict: any key but the ones below throws, so nothing unreviewed rides along.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ModKey.self)
        let known: Set<String> = ["id", "name", "author", "version", "look", "flags"]
        for key in c.allKeys where !known.contains(key.stringValue) {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "unknown key \(key.stringValue)")
        }
        id = try c.decode(String.self, forKey: ModKey("id"))
        name = try c.decode(String.self, forKey: ModKey("name"))
        author = try c.decodeIfPresent(String.self, forKey: ModKey("author")) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: ModKey("version")) ?? "1.0.0"
        look = try c.decodeIfPresent(SpaceLook.self, forKey: ModKey("look"))
        flags = try c.decodeIfPresent(ModFlags.self, forKey: ModKey("flags"))
    }

    /// Everything wrong with it, empty if it is sound.
    func validate() -> [ModError] {
        var errors: [ModError] = []
        if !Mod.isValidID(id) { errors.append(.badID) }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append(.emptyName) }
        if name.count > Mod.maxNameLength { errors.append(.nameTooLong) }
        if author.count > Mod.maxAuthorLength { errors.append(.authorTooLong) }
        if !Mod.isValidVersion(version) { errors.append(.badVersion) }
        if let flags {
            if let v = flags.dimUnloadedTabs, !(ModFlags.dimRange ~= v) { errors.append(.flagOutOfRange(.dimUnloadedTabs)) }
            if let v = flags.tabTextSize, !(ModFlags.tabTextSizeRange ~= v) { errors.append(.flagOutOfRange(.tabTextSize)) }
        }
        return errors
    }

    /// Reads and checks a manifest: unreadable (bad JSON, unknown key or flag, with the reason) or invalid (the errors).
    enum LoadFailure: Error, Equatable {
        case unreadable(String)
        case invalid([ModError])
    }

    static func load(_ data: Data) -> Result<Mod, LoadFailure> {
        let mod: Mod
        do { mod = try JSONDecoder().decode(Mod.self, from: data) } catch {
            return .failure(.unreadable(describe(error)))
        }
        let errors = mod.validate()
        return errors.isEmpty ? .success(mod) : .failure(.invalid(errors))
    }

    /// Reverse-DNS-ish: two or more dot-separated lowercase parts, each starting with a letter
    /// or digit and holding letters, digits and hyphens; 3…100 characters.
    static func isValidID(_ id: String) -> Bool {
        guard (3...100).contains(id.utf8.count) else { return false }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isASCII, first.isLowercase || first.isNumber else { return false }
            return part.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") } && part.last != "-"
        }
    }

    static func isValidVersion(_ v: String) -> Bool {
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        return (1...3).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return "not a mod manifest" }
        switch e {
        case .dataCorrupted(let ctx), .typeMismatch(_, let ctx), .valueNotFound(_, let ctx): return ctx.debugDescription
        case .keyNotFound(let key, _): return "missing \(key.stringValue)"
        @unknown default: return "not a mod manifest"
        }
    }
}

extension SpaceLook {
    /// The look to draw: defaults, then the enabled `mods` in order, then the space's own.
    static func resolve(mods: [Mod], own: SpaceLook?) -> Resolved {
        resolve(mods.compactMap(\.look) + [own].compactMap { $0 })
    }
}

/// Coding key for any string, so keys can be checked against a closed list.
struct ModKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Mod {
    private static func builtin(_ slug: String, _ name: String, flags: ModFlags, look: SpaceLook? = nil) -> Mod {
        Mod(id: "app.wayfinder.mods.\(slug)", name: name, author: "Wayfinder", version: "1.0.0", look: look, flags: flags)
    }

    /// Shipped with the app, one per switch.
    static let builtIns: [Mod] = [
        builtin("hover-close", "Close on Hover", flags: ModFlags(hoverOnlyClose: true)),
        builtin("big-mute", "Bigger Mute Button", flags: ModFlags(biggerMute: true)),
        builtin("dim-sleepers", "Dim Sleeping Tabs", flags: ModFlags(dimUnloadedTabs: 0.5)),
        builtin("large-tabs", "Larger Tab Text", flags: ModFlags(tabTextSize: 15), look: SpaceLook(density: .roomy)),
        builtin("sleek-border", "Sleek Border", flags: ModFlags(sleekBorder: true), look: SpaceLook(cornerRadius: 12, webInset: 6, webBorder: 1)),
        builtin("compact-find", "Compact Find Bar", flags: ModFlags(compactFindBar: true)),
        builtin("quiet-pins", "Hide Pinned Reset", flags: ModFlags(hidePinnedReset: true)),
        builtin("tidy-reset", "Reset on Hover", flags: ModFlags(resetOnHoverOnly: true)),
    ]
}
