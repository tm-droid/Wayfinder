import SwiftUI

// The Look editor, from the space menu's Edit Look…: a field of dots for the
// gradient's colours (round for the hue, out for how much), tracks for
// transparency, grain and angle, Light, Dark or Auto for this space, presets,
// an accent, and More for shape and type. Edits show at once, in this window;
// Done saves them and Cancel puts the look back. ⌥ while dragging moves a
// tenth as far; a double-click on a track puts it back.

struct LookEditor: View {
    @ObservedObject var browser: Browser
    let spaceID: UUID
    let close: () -> Void

    @State private var draft: SpaceLook
    @State private var selected = 0
    @State private var more = false
    /// Where the dragged dot began, so ⌥ can move it a tenth as far.
    @State private var anchor: CGPoint?

    init(browser: Browser, close: @escaping () -> Void) {
        self.browser = browser
        spaceID = browser.spaceID
        self.close = close
        _draft = State(initialValue: browser.space.look ?? SpaceLook())
    }

    private var now: SpaceLook.Resolved { SpaceLook.resolve([draft]) }
    private var stops: [String] { now.gradient }
    private let field: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Look of “\(browser.space.name)”").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)

            HStack(alignment: .top, spacing: 14) {
                dots
                VStack(alignment: .leading, spacing: 8) {
                    Button { add() } label: { Label("Add Colour", systemImage: "plus") }.disabled(stops.count >= 3)
                    Button { remove() } label: { Label(stops.count > 2 ? "Remove Colour" : "No Gradient", systemImage: "minus") }
                        .disabled(stops.isEmpty)
                }
                .buttonStyle(.link).font(.system(size: 12))
            }

            LookTrack(title: "Transparency", value: now.transparency, range: 0...1) { draft.transparency = $0 } reset: { draft.transparency = nil }
            LookTrack(title: "Grain", value: now.grain, range: 0...1) { draft.grain = $0 } reset: { draft.grain = nil }
            LookTrack(title: "Angle", value: now.angle, range: 0...360) { draft.angle = $0 } reset: { draft.angle = nil }

            Picker("", selection: Binding(get: { draft.scheme ?? .auto }, set: { draft.scheme = $0 == .auto ? nil : $0 })) {
                Text("Auto").tag(LookScheme.auto)
                Text("Light").tag(LookScheme.light)
                Text("Dark").tag(LookScheme.dark)
            }
            .pickerStyle(.segmented).labelsHidden()

            presets

            HStack {
                ColorPicker("Accent", selection: Binding(get: { Tint.color(now.accent ?? "#3478F6") ?? .blue },
                                                         set: { draft.accent = Self.hex($0) }))
                    .font(.system(size: 12))
                if draft.accent != nil { Button("Reset") { draft.accent = nil }.buttonStyle(.link).font(.system(size: 12)) }
            }

            DisclosureGroup("More", isExpanded: $more) {
                VStack(alignment: .leading, spacing: 10) {
                    LookTrack(title: "Corner radius", value: now.cornerRadius, range: SpaceLook.cornerRadiusRange) { draft.cornerRadius = $0 } reset: { draft.cornerRadius = nil }
                    Picker("Density", selection: Binding(get: { now.density }, set: { draft.density = $0 })) {
                        ForEach(LookDensity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Font", selection: Binding(get: { now.font }, set: { draft.font = $0 })) {
                        ForEach(LookFont.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Stepper("Tab text \(Int(now.tabTextSize)) pt", value: Binding(get: { now.tabTextSize }, set: { draft.tabTextSize = $0 }),
                            in: SpaceLook.tabTextSizeRange, step: 1)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12))

            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Done") { browser.setSpaceLook(spaceID, to: draft); close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .popoverGround()
        .onChange(of: draft) { _, look in browser.previewSpaceLook(spaceID, look.isEmpty ? nil : look) }
        // Gone by any road (Cancel, a click outside, another space) puts the saved look back.
        .onDisappear { browser.lookPreview = nil }
        .onChange(of: browser.spaceID) { _, _ in close() }
    }

    // MARK: Dots

    private var dots: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 0.55, brightness: 0.95) },
                                          center: .center, angle: .degrees(-90)))
            Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: field / 2))
            Circle().strokeBorder(Palette.hairline, lineWidth: 1)
            ForEach(Array(stops.enumerated()), id: \.offset) { i, hex in
                Circle().fill(Tint.color(hex) ?? .gray).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: i == selected ? 3 : 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(point(hex))
            }
        }
        .frame(width: field, height: field)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag($0) }.onEnded { _ in anchor = nil })
        .accessibilityLabel("Gradient colours")
    }

    private func point(_ hex: String) -> CGPoint {
        LookEdit.place(hex).map { LookEdit.point(hue: $0.hue, amount: $0.amount, in: field) } ?? CGPoint(x: field / 2, y: field / 2)
    }

    private func drag(_ g: DragGesture.Value) {
        guard !stops.isEmpty else { return }
        if anchor == nil {
            let near = stops.enumerated().min { dist($0.element, g.startLocation) < dist($1.element, g.startLocation) }
            if let near, dist(near.element, g.startLocation) < 18 { selected = near.offset }
            anchor = point(stops[min(selected, stops.count - 1)])
        }
        let fine = NSEvent.modifierFlags.contains(.option)
        let base = anchor ?? .zero
        let target = fine ? CGPoint(x: base.x + g.translation.width * 0.1, y: base.y + g.translation.height * 0.1) : g.location
        let at = LookEdit.place(at: target, in: field)
        var next = stops
        next[min(selected, next.count - 1)] = LookEdit.hex(hue: at.hue, amount: at.amount)
        draft.gradient = next
    }

    private func dist(_ hex: String, _ p: CGPoint) -> Double {
        let q = point(hex)
        return Double(hypot(q.x - p.x, q.y - p.y))
    }

    private func add() {
        draft.gradient = stops.isEmpty ? ["#FFD9C7", "#C7D4F7"] : LookEdit.adding(LookEdit.hex(hue: Double(stops.count) / 3, amount: 0.4), to: stops)
        selected = (draft.gradient?.count ?? 1) - 1
    }

    private func remove() {
        draft.gradient = LookEdit.removing(selected, from: stops)
        selected = 0
    }

    // MARK: Presets

    private var presets: some View {
        HStack(spacing: 8) {
            Button {
                draft.gradient = nil; draft.grain = nil; draft.transparency = nil
                draft.angle = nil; draft.scheme = nil; draft.accent = nil
            } label: {
                Circle().strokeBorder(Palette.hairline, lineWidth: 1).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "slash.circle").font(.system(size: 11)).foregroundStyle(Palette.muted))
            }
            .help("No look")
            ForEach(LookPreset.all) { preset in
                Button {
                    draft.gradient = preset.look.gradient; draft.angle = preset.look.angle; draft.grain = preset.look.grain
                    draft.transparency = preset.look.transparency; draft.scheme = preset.look.scheme; draft.accent = preset.look.accent
                    selected = 0
                } label: {
                    Circle().fill(LinearGradient(colors: (preset.look.gradient ?? []).compactMap(Tint.color),
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22).overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                }
                .help(preset.name)
            }
        }
        .buttonStyle(.plain)
    }

    private static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// A labelled slider: ⌥ drags a tenth as far, a double-click puts it back.
struct LookTrack: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void
    let reset: () -> Void

    @State private var start: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
            GeometryReader { geo in
                let span = range.upperBound - range.lowerBound
                let x = CGFloat((value - range.lowerBound) / span) * geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline).frame(height: 4)
                    Capsule().fill(Palette.muted).frame(width: x, height: 4)
                    Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1).offset(x: x - 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture(count: 2).onEnded { reset() })
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    if NSEvent.modifierFlags.contains(.option) {
                        if start == nil { start = value }
                        set(LookEdit.dragged(start ?? value, by: Double(g.translation.width / geo.size.width) * span, fine: true, in: range))
                    } else {
                        start = nil
                        set(LookEdit.dragged(range.lowerBound, by: Double(g.location.x / geo.size.width) * span, fine: false, in: range))
                    }
                }.onEnded { _ in start = nil })
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { dir in
            let step = (range.upperBound - range.lowerBound) / 20
            set(LookEdit.dragged(value, by: dir == .increment ? step : -step, fine: false, in: range))
        }
    }
}
