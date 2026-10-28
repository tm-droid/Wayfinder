import Foundation

// A mod's preferences, as Zen's mods have: a checkbox, a dropdown of fixed
// options, or a short string. They are declarative values only. A checkbox or
// dropdown may be bound to one of the closed list of flags (ModFlag), which is
// how a choice changes anything; a string is stored and shown and bound to
// nothing. Nothing here is ever evaluated, run or turned into CSS.

extension ModFlag {
    /// On or off; the others take a number.
    var isToggle: Bool { self != .dimUnloadedTabs && self != .tabTextSize }

    var range: ClosedRange<Double>? {
        switch self {
        case .dimUnloadedTabs: return ModFlags.dimRange
        case .tabTextSize: return ModFlags.tabTextSizeRange
        default: return nil
        }
    }

    /// Close crosses and the pinned reset arrow already show only under the
    /// pointer, so these two change nothing. Said so on the Mods page.
    var isAlreadyDefault: Bool { self == .hoverOnlyClose || self == .resetOnHoverOnly }
}

extension ModFlags {
    /// The flags this one mentions.
    var present: [ModFlag] {
        ModFlag.allCases.filter { flag in
            switch flag {
            case .hoverOnlyClose: return hoverOnlyClose != nil
            case .biggerMute: return biggerMute != nil
            case .dimUnloadedTabs: return dimUnloadedTabs != nil
            case .tabTextSize: return tabTextSize != nil
            case .sleekBorder: return sleekBorder != nil
            case .compactFindBar: return compactFindBar != nil
            case .hidePinnedReset: return hidePinnedReset != nil
            case .resetOnHoverOnly: return resetOnHoverOnly != nil
            }
        }
    }

    mutating func set(_ flag: ModFlag, toggle value: Bool?) {
        switch flag {
        case .hoverOnlyClose: hoverOnlyClose = value
        case .biggerMute: biggerMute = value
        case .sleekBorder: sleekBorder = value
        case .compactFindBar: compactFindBar = value
        case .hidePinnedReset: hidePinnedReset = value
        case .resetOnHoverOnly: resetOnHoverOnly = value
        case .dimUnloadedTabs, .tabTextSize: break
        }
    }

    mutating func set(_ flag: ModFlag, number value: Double?) {
        switch flag {
        case .dimUnloadedTabs: dimUnloadedTabs = value
        case .tabTextSize: tabTextSize = value
        default: break
        }
    }
}

/// What a preference holds.
enum ModPrefValue: Codable, Equatable {
    case on(Bool)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .on(b) } else { self = .text(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .on(let b): try c.encode(b)
        case .text(let s): try c.encode(s)
        }
    }
}

struct ModPref: Codable, Equatable, Identifiable {
    enum Kind: String, CaseIterable { case checkbox, dropdown, string }

    struct Option: Codable, Equatable {
        var value: String
        var label: String
    }

    enum Problem: Equatable {
        case badID, duplicateID
        case emptyLabel, labelTooLong
        case optionsNotAllowed, tooFewOptions, tooManyOptions, badOption, duplicateOption
        case badDefault
        case maxLengthNotAllowed, maxLengthOutOfRange
        case flagNotAllowed, flagNeedsToggle, flagNeedsNumbers, optionOutOfRange

        var message: String {
            switch self {
            case .badID: return "the id must be 1 to \(ModPref.maxIDLength) lowercase letters, digits or hyphens."
            case .duplicateID: return "another preference already uses this id."
            case .emptyLabel: return "it needs a label."
            case .labelTooLong: return "the label is longer than \(ModPref.maxLabelLength) characters."
            case .optionsNotAllowed: return "only a dropdown has options."
            case .tooFewOptions: return "a dropdown needs at least 2 options."
            case .tooManyOptions: return "a dropdown can have at most \(ModPref.maxOptions) options."
            case .badOption: return "each option needs a value of up to \(ModPref.maxOptionValueLength) characters and a label of up to \(ModPref.maxLabelLength)."
            case .duplicateOption: return "two options share a value."
            case .badDefault: return "the default does not fit the preference."
            case .maxLengthNotAllowed: return "only a string has a maxLength."
            case .maxLengthOutOfRange: return "maxLength must be between 1 and \(ModPref.maxStringLength)."
            case .flagNotAllowed: return "a string cannot be bound to a flag."
            case .flagNeedsToggle: return "a checkbox can only be bound to an on-or-off flag."
            case .flagNeedsNumbers: return "a dropdown can only be bound to a numeric flag, with a number for every option."
            case .optionOutOfRange: return "an option's number is outside what the flag allows."
            }
        }
    }

    static let maxIDLength = 32
    static let maxLabelLength = 60
    static let maxOptions = 12
    static let maxOptionValueLength = 40
    static let maxStringLength = 200
    static let defaultStringLength = 80

    var id: String
    var label: String
    var kind: Kind
    /// Nil: off for a checkbox, the first option for a dropdown, empty for a string.
    var initial: ModPrefValue?
    var options: [Option]
    /// Strings only.
    var maxLength: Int
    /// The flag a checkbox or dropdown sets.
    var flag: ModFlag?

    init(id: String, label: String, kind: Kind, initial: ModPrefValue? = nil, options: [Option] = [],
         maxLength: Int = ModPref.defaultStringLength, flag: ModFlag? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.initial = initial
        self.options = options
        self.maxLength = maxLength
        self.flag = flag
    }

    private static let known: Set<String> = ["id", "label", "type", "default", "options", "maxLength", "flag"]

    /// Strict: an unknown key or type throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ModKey.self)
        for key in c.allKeys where !ModPref.known.contains(key.stringValue) {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "unknown preference key \(key.stringValue)")
        }
        id = try c.decode(String.self, forKey: ModKey("id"))
        label = try c.decode(String.self, forKey: ModKey("label"))
        let type = try c.decode(String.self, forKey: ModKey("type"))
        guard let kind = Kind(rawValue: type) else {
            throw DecodingError.dataCorruptedError(forKey: ModKey("type"), in: c, debugDescription: "unknown preference type \(type)")
        }
        self.kind = kind
        initial = try c.decodeIfPresent(ModPrefValue.self, forKey: ModKey("default"))
        options = try c.decodeIfPresent([Option].self, forKey: ModKey("options")) ?? []
        maxLength = try c.decodeIfPresent(Int.self, forKey: ModKey("maxLength")) ?? ModPref.defaultStringLength
        if let name = try c.decodeIfPresent(String.self, forKey: ModKey("flag")) {
            guard let flag = ModFlag(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: ModKey("flag"), in: c, debugDescription: "unknown flag \(name)")
            }
            self.flag = flag
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ModKey.self)
        try c.encode(id, forKey: ModKey("id"))
        try c.encode(label, forKey: ModKey("label"))
        try c.encode(kind.rawValue, forKey: ModKey("type"))
        try c.encodeIfPresent(initial, forKey: ModKey("default"))
        if kind == .dropdown { try c.encode(options, forKey: ModKey("options")) }
        if kind == .string { try c.encode(maxLength, forKey: ModKey("maxLength")) }
        try c.encodeIfPresent(flag?.rawValue, forKey: ModKey("flag"))
    }

    /// The value in force when the user has chosen nothing.
    var defaultValue: ModPrefValue {
        if let initial, accepts(initial) { return initial }
        switch kind {
        case .checkbox: return .on(false)
        case .dropdown: return .text(options.first?.value ?? "")
        case .string: return .text("")
        }
    }

    /// Whether `value` is one this preference can hold.
    func accepts(_ value: ModPrefValue) -> Bool {
        switch (kind, value) {
        case (.checkbox, .on): return true
        case (.dropdown, .text(let s)): return options.contains { $0.value == s }
        case (.string, .text(let s)): return s.count <= maxLength && !s.unicodeScalars.contains { $0.properties.generalCategory == .control }
        default: return false
        }
    }

    /// Everything wrong with it; `duplicate` is whether an earlier preference has its id.
    func problems(duplicate: Bool) -> [Problem] {
        var out: [Problem] = []
        if !ModPref.isValidID(id) { out.append(.badID) }
        if duplicate { out.append(.duplicateID) }
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.emptyLabel) }
        if label.count > ModPref.maxLabelLength { out.append(.labelTooLong) }
        switch kind {
        case .checkbox, .string:
            if !options.isEmpty { out.append(.optionsNotAllowed) }
        case .dropdown:
            if options.count < 2 { out.append(.tooFewOptions) }
            if options.count > ModPref.maxOptions { out.append(.tooManyOptions) }
            let shown = options.prefix(ModPref.maxOptions)
            if shown.contains(where: { $0.value.isEmpty || $0.value.count > ModPref.maxOptionValueLength
                || $0.label.trimmingCharacters(in: .whitespaces).isEmpty || $0.label.count > ModPref.maxLabelLength }) {
                out.append(.badOption)
            }
            if Set(shown.map(\.value)).count != shown.count { out.append(.duplicateOption) }
        }
        if kind != .string, maxLength != ModPref.defaultStringLength { out.append(.maxLengthNotAllowed) }
        if kind == .string, !(1...ModPref.maxStringLength ~= maxLength) { out.append(.maxLengthOutOfRange) }
        if let initial, !accepts(initial) { out.append(.badDefault) }
        if let flag {
            switch kind {
            case .string: out.append(.flagNotAllowed)
            case .checkbox: if !flag.isToggle { out.append(.flagNeedsToggle) }
            case .dropdown:
                if let range = flag.range {
                    let numbers = options.map { Double($0.value) }
                    if numbers.contains(where: { $0 == nil || !$0!.isFinite }) { out.append(.flagNeedsNumbers) }
                    else if numbers.contains(where: { !(range ~= $0!) }) { out.append(.optionOutOfRange) }
                } else { out.append(.flagNeedsNumbers) }
            }
        }
        return out
    }

    static func isValidID(_ id: String) -> Bool {
        (1...maxIDLength ~= id.utf8.count) && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}

extension Mod {
    /// The mod's flags as the user's choices leave them: the manifest's own,
    /// then each bound preference over them. A checkbox left off says nothing.
    func flags(with values: [String: ModPrefValue]) -> ModFlags {
        var f = flags ?? ModFlags()
        for pref in prefs {
            guard let flag = pref.flag else { continue }
            let value = values[pref.id].flatMap { pref.accepts($0) ? $0 : nil } ?? pref.defaultValue
            switch (pref.kind, value) {
            case (.checkbox, .on(let on)): f.set(flag, toggle: on ? true : nil)
            case (.dropdown, .text(let s)): f.set(flag, number: Double(s))
            default: break
            }
        }
        return f
    }
}
