import SwiftUI

// The active space's look as the views draw it: the resolved tokens
// (SpaceLook.swift) in the environment, a gradient-and-grain ground for the
// sidebar and the window, and the pure maths the Look editor uses.

struct Tint: Equatable {
    var look: SpaceLook.Resolved
    /// The enabled mods' switches, later mods winning (see Mods in ModStore.swift).
    var flags = ModFlags()

    static let none = Tint(look: SpaceLook.defaults)

    /// The look of the space with `id` among `spaces`, under `mods` (the enabled ones, in order: `Mods.enabled`). An editor's
    /// unsaved `preview` of that space stands in for its saved look.
    static func of(_ spaces: [Space], active id: UUID, mods: [Mod] = [], preview: (id: UUID, look: SpaceLook?)? = nil) -> Tint {
        let space = spaces.first { $0.id == id } ?? spaces.first
        let own = preview.flatMap { $0.id == space?.id ? $0 : nil }.map(\.look) ?? space?.look
        return Tint(look: SpaceLook.resolve(mods: mods, own: own), flags: ModFlags.merge(mods))
    }

    /// The size tab titles are set in: a mod's or the space's choice, else `normal`.
    func tabTextSize(else normal: CGFloat) -> CGFloat {
        look.tabTextSize == SpaceLook.defaults.tabTextSize ? normal : CGFloat(look.tabTextSize)
    }

    /// How much of a row shows: a tab that is asleep and not the one on screen fades as the mods say.
    func dims(asleep: Bool, live: Bool) -> Double {
        guard asleep, !live, let fade = flags.dimUnloadedTabs else { return 1 }
        return 1 - min(max(fade, ModFlags.dimRange.lowerBound), ModFlags.dimRange.upperBound)
    }

    var hasGround: Bool { !look.gradient.isEmpty }
    var scheme: LookScheme { look.scheme }
    var accent: Color? { look.accent.flatMap(Tint.color) }

    /// How much of the gradient shows. Solid, for Reduce Transparency and
    /// Increase Contrast: one quiet wash of the first colour, no grain.
    func opacity(solid: Bool) -> Double { solid ? 0.22 : 1 - look.transparency }

    /// The stops, even along the gradient's line.
    func gradient(solid: Bool) -> LinearGradient {
        let colours = solid ? [look.gradient.first.flatMap(Tint.color) ?? .clear] : look.gradient.compactMap(Tint.color)
        let heading = look.angle * .pi / 180
        let dx = sin(heading) / 2, dy = -cos(heading) / 2
        return LinearGradient(colors: colours.count == 1 ? colours + colours : colours,
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    static func color(_ hex: String) -> Color? {
        guard let n = SpaceLook.normalizedHex(hex) else { return nil }
        let v = n.dropFirst().chunks(2).compactMap { UInt8($0, radix: 16) }.map { Double($0) / 255 }
        guard v.count >= 3 else { return nil }
        return Color(.sRGB, red: v[0], green: v[1], blue: v[2], opacity: v.count > 3 ? v[3] : 1)
    }

    /// How a space switch eases between looks.
    static var animation: Animation? { Motion.reduced ? nil : Motion.light ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.4) }
}

private extension Substring {
    func chunks(_ n: Int) -> [Substring] {
        var out: [Substring] = [], rest = self
        while !rest.isEmpty { out.append(rest.prefix(n)); rest = rest.dropFirst(n) }
        return out
    }
}

private struct TintKey: EnvironmentKey {
    static let defaultValue = Tint.none
}

extension EnvironmentValues {
    var tint: Tint {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

/// The gradient and grain over the base colour, taking no clicks.
struct TintGround: View {
    /// The space on screen: a change of look eases only when it is this that
    /// changed, never while the editor drags a colour.
    let space: UUID
    @Environment(\.tint) private var tint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let solid = reduceTransparency || contrast == .increased
        ZStack {
            if tint.hasGround {
                Rectangle().fill(tint.gradient(solid: solid)).opacity(tint.opacity(solid: solid))
                if !solid, tint.look.grain > 0 {
                    Image(nsImage: Grain.tile).resizable(resizingMode: .tile)
                        .opacity(tint.look.grain * 0.5).blendMode(.overlay)
                }
            }
        }
        .animation(Tint.animation, value: space)
        .allowsHitTesting(false)
    }
}

enum Grain {
    /// One small noise image, made on first use and tiled.
    static let tile: NSImage = {
        let side = 96
        var rng = SystemRandomNumberGenerator()
        var px = [UInt8](repeating: 0, count: side * side * 2)
        for i in 0..<side * side {
            px[i * 2] = UInt8.random(in: 0...255, using: &rng)
            px[i * 2 + 1] = 255
        }
        let provider = CGDataProvider(data: Data(px) as CFData)
        let image = provider.flatMap {
            CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: side * 2,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return image.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) } ?? NSImage()
    }()
}

// MARK: - Editor maths

enum LookEdit {
    /// A dot's place as a hue (0 to 1 around, 0 at the top) and an amount
    /// (0 at the centre to 1 at the rim).
    static func place(_ hex: String) -> (hue: Double, amount: Double)? {
        guard let n = SpaceLook.normalizedHex(hex), let c = NSColor(hexString: n) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s))
    }

    static func hex(hue: Double, amount: Double) -> String {
        let c = NSColor(hue: CGFloat(min(max(hue, 0), 1)), saturation: CGFloat(min(max(amount, 0), 1)), brightness: 0.92, alpha: 1)
            .usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    /// The hue and amount for a point (x, y from the field's top-left) in a
    /// field `size` across.
    static func place(at point: CGPoint, in size: CGFloat) -> (hue: Double, amount: Double) {
        let dx = Double(point.x - size / 2), dy = Double(point.y - size / 2)
        var hue = atan2(dx, -dy) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return (hue, min(1, hypot(dx, dy) / Double(size / 2)))
    }

    static func point(hue: Double, amount: Double, in size: CGFloat) -> CGPoint {
        let r = amount * Double(size / 2), t = hue * 2 * .pi
        return CGPoint(x: Double(size / 2) + r * sin(t), y: Double(size / 2) - r * cos(t))
    }

    /// A drag of `delta` from `start`; ⌥ moves a tenth as far.
    static func dragged(_ start: Double, by delta: Double, fine: Bool, in range: ClosedRange<Double> = 0...1) -> Double {
        min(max(start + delta * (fine ? 0.1 : 1), range.lowerBound), range.upperBound)
    }

    /// The gradient with `hex` added (at most three stops), or the stop at
    /// `index` removed (at least two stay). Nil when nothing changes.
    static func adding(_ hex: String, to stops: [String]) -> [String]? { stops.count < 3 ? stops + [hex] : nil }
    static func removing(_ index: Int, from stops: [String]) -> [String]? {
        guard stops.count > 2, stops.indices.contains(index) else { return nil }
        var s = stops
        s.remove(at: index)
        return s
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let v = hexString.dropFirst().chunks(2).compactMap { UInt8($0, radix: 16) }.map { CGFloat($0) / 255 }
        guard v.count >= 3 else { return nil }
        self.init(srgbRed: v[0], green: v[1], blue: v[2], alpha: v.count > 3 ? v[3] : 1)
    }
}

// MARK: - Presets

struct LookPreset: Identifiable {
    let name: String
    let look: SpaceLook
    var id: String { name }

    private static func make(_ name: String, _ stops: [String], _ angle: Double, accent: String, grain: Double = 0.25,
                             transparency: Double = 0.35, scheme: LookScheme? = nil) -> LookPreset {
        LookPreset(name: name, look: SpaceLook(gradient: stops, angle: angle, grain: grain, transparency: transparency,
                                               scheme: scheme == .auto ? nil : scheme, accent: accent))
    }

    static let all: [LookPreset] = [
        make("Dawn", ["#FFD9C7", "#FFC2D6"], 160, accent: "#E8663D"),
        make("Dusk", ["#C9B8F5", "#F3B7C9", "#FFD6A8"], 135, accent: "#8A5CF6"),
        make("Sea", ["#BFE3F2", "#9CC8E8"], 180, accent: "#2F7DD1"),
        make("Moss", ["#D4E8C8", "#B6D6B4"], 150, accent: "#3E8F5A"),
        make("Ember", ["#F6C79A", "#EE9B8B", "#C77B9E"], 125, accent: "#D2492F", grain: 0.35),
        make("Lilac", ["#E3D5F7", "#C7D4F7"], 200, accent: "#6C5CE7"),
        make("Slate", ["#B8C0CC", "#8F9AAB"], 170, accent: "#4A5B78", grain: 0.15),
        make("Midnight", ["#2B3A67", "#4B3F72", "#1F2A44"], 145, accent: "#7C8CFF", grain: 0.3, transparency: 0.15, scheme: .dark),
    ]
}
