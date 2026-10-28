import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Settings › Mods: the built-in and installed mods in the order they apply
// (later ones win, the space's own Look wins over them all), each with an
// on switch, arrows to move it, a remove button for the ones you installed,
// and its own preferences.

struct ModsPage: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var store: ModStore
    @State private var problem: String?

    init(browser: Browser) {
        self.browser = browser
        _store = ObservedObject(wrappedValue: ModStore.shared(browser.profileID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                SettingRow(icon: "square.and.arrow.down", title: "Install from file…",
                           detail: "A mod is a small JSON file of look settings and switches. It cannot run anything",
                           more: "Up to 64 KB. A file with a css key, a switch or preference type Wayfinder does not know, or a value out of range is refused, not half applied.") {
                    Pill("Choose…", action: install)
                }
                if let problem {
                    Rule()
                    Text(problem)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let mods = store.state.all
            GroupBlock(title: "In the order they apply", icon: "list.number") {
                Card {
                    ForEach(Array(mods.enumerated()), id: \.element.id) { index, mod in
                        if index > 0 { Rule() }
                        ModRow(mod: mod, store: store, first: index == 0, last: index == mods.count - 1)
                    }
                }
            }
        }
    }

    private func install() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Wayfinder mod (.json, up to 64 KB)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        problem = store.install(from: url)
    }

    private struct ModRow: View {
        let mod: Mod
        @ObservedObject var store: ModStore
        let first: Bool
        let last: Bool

        private var builtIn: Bool { store.state.isBuiltIn(mod.id) }
        private var on: Binding<Bool> {
            Binding(get: { store.state.isEnabled(mod.id) }, set: { value in store.change { $0.setEnabled(mod.id, value) } })
        }

        /// Close crosses and the pinned reset arrow already show only under the pointer.
        private var inert: Bool {
            let used = mod.flags?.present ?? []
            return !used.isEmpty && used.allSatisfy(\.isAlreadyDefault) && mod.look == nil
        }

        private var detail: String {
            var parts = [builtIn ? "Comes with Wayfinder" : mod.author.isEmpty ? "Installed" : "By \(mod.author)", "v\(mod.version)"]
            if inert { parts.append("already how Wayfinder works") }
            return parts.joined(separator: " · ")
        }

        var body: some View {
            VStack(spacing: 0) {
                SettingRow(icon: builtIn ? "wand.and.stars" : "puzzlepiece", title: mod.name, detail: detail) {
                    HStack(spacing: 8) {
                        arrow("chevron.up", help: "Apply earlier", disabled: first) { store.change { $0.move(mod.id, by: -1) } }
                        arrow("chevron.down", help: "Apply later", disabled: last) { store.change { $0.move(mod.id, by: 1) } }
                        if !builtIn {
                            arrow("trash", help: "Remove \(mod.name)", disabled: false) { store.change { $0.remove(mod.id) } }
                        }
                        Switch(on: on)
                            .accessibilityLabel(mod.name)
                    }
                }
                ForEach(mod.prefs) { pref in
                    PrefRow(mod: mod, pref: pref, store: store)
                        .disabled(!on.wrappedValue)
                        .opacity(on.wrappedValue ? 1 : 0.5)
                }
            }
        }

        private func arrow(_ icon: String, help: String, disabled: Bool, _ act: @escaping () -> Void) -> some View {
            Button(action: act) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.3 : 1)
            .help(help)
            .accessibilityLabel(help)
        }
    }

    private struct PrefRow: View {
        let mod: Mod
        let pref: ModPref
        @ObservedObject var store: ModStore
        @State private var text = ""

        private var value: ModPrefValue { store.state.value(of: pref, in: mod) }
        private func set(_ v: ModPrefValue) { store.change { $0.setValue(v, pref: pref.id, of: mod.id) } }

        var body: some View {
            HStack(spacing: 10) {
                Text(pref.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                control
            }
            .padding(.leading, 52)
            .padding(.trailing, 14)
            .padding(.bottom, 10)
            .onAppear { if case .text(let s) = value { text = s } }
        }

        @ViewBuilder
        private var control: some View {
            switch pref.kind {
            case .checkbox:
                Switch(on: Binding(get: { value == .on(true) }, set: { set(.on($0)) }))
                    .accessibilityLabel(pref.label)
            case .dropdown:
                Menu {
                    ForEach(pref.options, id: \.value) { option in
                        Button(option.label) { set(.text(option.value)) }
                    }
                } label: {
                    Text(pref.options.first { .text($0.value) == value }?.label ?? "")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(pref.label)
            case .string:
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 180)
                    .onChange(of: text) { _, new in
                        if new.count > pref.maxLength { text = String(new.prefix(pref.maxLength)) }
                    }
                    .onSubmit { set(.text(text)) }
                    .accessibilityLabel(pref.label)
            }
        }
    }
}
