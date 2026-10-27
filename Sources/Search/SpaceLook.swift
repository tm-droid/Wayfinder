import Foundation

// A space's look as theme tokens, Zen/Arc style: a gradient behind the
// sidebar, grain, an accent, and a few shape and type choices.
//
// Every field is optional so a look can be partial: a mod sets only the
// corner radius, a space only its gradient. `resolve` layers them, built-in
// defaults first, then each enabled mod in the user's order (later wins),
// then the space's own look, and clamps what is out of range. Values that
// cannot be read (a colour that is not hex, a font this version lacks) are
// dropped rather than failing the whole look, so a look from a newer version
// still loads.

enum LookDensity: String, Codable, CaseIterable {
    case compact, regular, roomy
}

enum LookFont: String, Codable, CaseIterable {
    case system, rounded, serif, mono
}

struct SpaceLook: Codable, Equatable {
    /// Two or three colours as "#RRGGBB" or "#RRGGBBAA".
    var gradient: [String]?
    /// Degrees, 0 pointing up and turning clockwise.
    var angle: Double?
    var grain: Double?
    var accent: String?
    var cornerRadius: Double?
    var density: LookDensity?
    var tabTextSize: Double?
    var font: LookFont?
    /// Space between the window and the web area, in points.
    var webInset: Double?
    var webBorder: Double?

    init(gradient: [String]? = nil, angle: Double? = nil, grain: Double? = nil, accent: String? = nil,
         cornerRadius: Double? = nil, density: LookDensity? = nil, tabTextSize: Double? = nil,
         font: LookFont? = nil, webInset: Double? = nil, webBorder: Double? = nil) {
        self.gradient = gradient
        self.angle = angle
        self.grain = grain
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.density = density
        self.tabTextSize = tabTextSize
        self.font = font
        self.webInset = webInset
        self.webBorder = webBorder
    }

    /// Reads whatever is there; a field of the wrong type or an unknown
    /// choice is left nil, and keys it does not know are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gradient = try? c.decodeIfPresent([String].self, forKey: .gradient)
        angle = try? c.decodeIfPresent(Double.self, forKey: .angle)
        grain = try? c.decodeIfPresent(Double.self, forKey: .grain)
        accent = try? c.decodeIfPresent(String.self, forKey: .accent)
        cornerRadius = try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)
        density = try? c.decodeIfPresent(LookDensity.self, forKey: .density)
        tabTextSize = try? c.decodeIfPresent(Double.self, forKey: .tabTextSize)
        font = try? c.decodeIfPresent(LookFont.self, forKey: .font)
        webInset = try? c.decodeIfPresent(Double.self, forKey: .webInset)
        webBorder = try? c.decodeIfPresent(Double.self, forKey: .webBorder)
    }

    var isEmpty: Bool { self == SpaceLook() }

    // MARK: Ranges

    static let angleRange = 0.0...360.0
    static let grainRange = 0.0...1.0
    static let cornerRadiusRange = 0.0...32.0
    static let tabTextSizeRange = 9.0...20.0
    static let webInsetRange = 0.0...24.0
    static let webBorderRange = 0.0...4.0

    // MARK: Resolving

    /// What the sidebar and web area draw with: every field set and in range.
    struct Resolved: Equatable {
        /// Empty for no gradient.
        var gradient: [String]
        var angle: Double
        var grain: Double
        var accent: String?
        var cornerRadius: Double
        var density: LookDensity
        var tabTextSize: Double
        var font: LookFont
        var webInset: Double
        var webBorder: Double
    }

    static let defaults = Resolved(gradient: [], angle: 135, grain: 0, accent: nil, cornerRadius: 10, density: .regular,
                                   tabTextSize: 13, font: .system, webInset: 0, webBorder: 0)

    /// Defaults, then `layers` in order (later wins), clamped. Pass the enabled
    /// mods' looks in the user's order, then the space's own.
    static func resolve(_ layers: [SpaceLook]) -> Resolved {
        var r = defaults
        for layer in layers {
            if let stops = layer.cleanGradient { r.gradient = stops }
            if let v = layer.angle, v.isFinite { r.angle = clamp(v, angleRange) }
            if let v = layer.grain, v.isFinite { r.grain = clamp(v, grainRange) }
            if let v = layer.accent.flatMap(normalizedHex) { r.accent = v }
            if let v = layer.cornerRadius, v.isFinite { r.cornerRadius = clamp(v, cornerRadiusRange) }
            if let v = layer.density { r.density = v }
            if let v = layer.tabTextSize, v.isFinite { r.tabTextSize = clamp(v, tabTextSizeRange) }
            if let v = layer.font { r.font = v }
            if let v = layer.webInset, v.isFinite { r.webInset = clamp(v, webInsetRange) }
            if let v = layer.webBorder, v.isFinite { r.webBorder = clamp(v, webBorderRange) }
        }
        return r
    }

    /// "#RRGGBB" or "#RRGGBBAA" in capitals; "#RGB" is widened. Nil if it is not a colour.
    static func normalizedHex(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.allSatisfy(\.isASCII), hex.allSatisfy(\.isHexDigit) else { return nil }
        switch hex.count {
        case 3: hex = hex.map { "\($0)\($0)" }.joined()
        case 6, 8: break
        default: return nil
        }
        return "#" + hex.uppercased()
    }

    /// The gradient's readable stops, at most three; nil unless at least two read.
    private var cleanGradient: [String]? {
        guard let gradient else { return nil }
        let stops = gradient.compactMap(SpaceLook.normalizedHex).prefix(3)
        return stops.count >= 2 ? Array(stops) : nil
    }

    private static func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
