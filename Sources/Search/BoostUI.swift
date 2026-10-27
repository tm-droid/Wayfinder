import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The editor for a boost, the list of them in Settings › Browsing, and the
// sheet an import is read through (see Boost.swift for what each may do).

extension Boosts {
    /// Page › Boost This Site…: the boost for this site, or a new one.
    @MainActor static func edit(in browser: Browser) {
        guard let tab = browser.active, tab.isWeb, let host = Dusk.host(of: tab.address) else {
            browser.announce("Open a site first")
            return
        }
        BoostSheet.present(shared.boost(for: host) ?? Boost(name: host, hosts: [host]), browser: browser)
    }

    /// Put changes on the pages already up: their scripts are set when a
    /// document starts, so the ones on this tab reload.
    @MainActor func refresh(_ browser: Browser) {
        for tab in browser.tabs where tab.isWeb && !tab.shy {
            tab.arm(hiding: browser.curtain.css(on: browser.curtain.host(of: tab.address)))
        }
        browser.active?.reload()
    }
}

/// A sheet over the front window, for a SwiftUI view that finishes itself.
@MainActor
enum BoostSheet {
    private static func show<V: View>(_ make: (@escaping () -> Void) -> V) {
        guard let parent = NSApp.keyWindow else { return }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: make { [weak window, weak parent] in
            if let window { parent?.endSheet(window) }
        })
        parent.beginSheet(window)
    }

    static func present(_ boost: Boost, browser: Browser) {
        show { done in BoostEditor(boost: boost, browser: browser, done: done) }
    }

    static func review(_ candidates: [BoostCandidate], browser: Browser) {
        show { done in BoostImportSheet(candidates: candidates, browser: browser, done: done) }
    }
}

// MARK: - the editor

struct BoostEditor: View {
    @State var boost: Boost
    let browser: Browser
    let done: () -> Void

    @State private var hostsText = ""
    @State private var hideText = ""
    @State private var sized = false
    @State private var accented = false
    @State private var accent = Color.blue
    @State private var fonted = false
    @State private var advanced = false
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Boost").font(.headline)
            TextField("Name", text: $boost.name)
            TextField("Sites, separated by commas", text: $hostsText)
            Toggle("Include subdomains", isOn: $boost.subdomains)
            Divider()
            Toggle("Dark", isOn: $boost.dark)
            HStack {
                Toggle("Font", isOn: $fonted)
                TextField("Font family", text: Binding(get: { boost.font ?? "" }, set: { boost.font = $0 }))
                    .disabled(!fonted)
            }
            HStack {
                Toggle("Text size", isOn: $sized)
                Slider(value: Binding(get: { Double(boost.textSize ?? 100) }, set: { boost.textSize = Int($0 / 5) * 5 }), in: 50...200)
                    .disabled(!sized)
                Text("\(boost.textSize ?? 100)%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Toggle("Accent colour", isOn: $accented)
                ColorPicker("", selection: $accent).labelsHidden().disabled(!accented)
            }
            Text("Hide, one selector per line").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $hideText).font(.system(.caption, design: .monospaced)).frame(height: 48)
                .border(Color.secondary.opacity(0.3))
            Text("CSS").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $boost.css).font(.system(.caption, design: .monospaced)).frame(height: 110)
                .border(Color.secondary.opacity(0.3))
            DisclosureGroup("Advanced", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A script runs on the sites above with full access to what you see and type there. Write only what you understand; never paste one from someone else.")
                        .font(.caption).foregroundStyle(.orange)
                    TextEditor(text: Binding(get: { boost.js ?? "" }, set: { boost.js = $0 }))
                        .font(.system(.caption, design: .monospaced)).frame(height: 110)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            Text(boost.summary).font(.caption).foregroundStyle(.secondary)
            if shown, let problem = candidate.problem { Text(problem).font(.caption).foregroundStyle(.red) }
            HStack {
                if Boosts.shared.boost(boost.id) != nil {
                    Button("Delete", role: .destructive) {
                        Boosts.shared.remove(boost.id)
                        Boosts.shared.refresh(browser)
                        done()
                    }
                }
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18)
        .frame(width: 460)
        .onAppear {
            hostsText = boost.hosts.joined(separator: ", ")
            hideText = boost.hide.joined(separator: "\n")
            fonted = !(boost.font ?? "").isEmpty
            sized = boost.textSize != nil
            if let hex = boost.accent, Boost.isHex(hex) {
                accented = true
                accent = Color(nsColor: NSColor(hex: hex))
            }
            advanced = boost.hasScript
        }
    }

    /// The boost as the fields stand.
    private var candidate: Boost {
        var b = boost
        b.hosts = hostsText.split(separator: ",").map { Boost.normal(String($0)) }.filter { !$0.isEmpty }
        b.hide = hideText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !fonted || (b.font ?? "").isEmpty { b.font = nil }
        if !sized { b.textSize = nil }
        b.accent = accented ? NSColor(accent).hex : nil
        if !b.hasScript { b.js = nil }
        // Written here, so it is one's own: no longer waiting to be kept.
        if b.js != nil { b.imported = false }
        return b
    }

    private func save() {
        shown = true
        let b = candidate
        guard b.problem == nil, Boosts.shared.save(b) else { return }
        Boosts.shared.refresh(browser)
        done()
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

// MARK: - reading an import

/// Each script in a file, in full, with the sites it would run on. Nothing
/// runs unless its switch is on; the boosts themselves come in off.
struct BoostImportSheet: View {
    let candidates: [BoostCandidate]
    let browser: Browser
    let done: () -> Void

    @State private var allowed: Set<UUID> = []
    @State private var subdomains: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring in \(candidates.count) boost\(candidates.count == 1 ? "" : "es")").font(.headline)
            Text("They come in off. Try one on a tab before keeping it. A script can read and change everything on its sites, so each is shown in full, and runs only if you allow it.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(candidates) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.boost.name.isEmpty ? item.boost.hosts.joined(separator: ", ") : item.boost.name).font(.subheadline.bold())
                            Text("Sites: \(item.boost.hosts.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                            if item.wantsSubdomains {
                                Toggle("Also every subdomain of those sites", isOn: Binding(
                                    get: { subdomains.contains(item.id) },
                                    set: { if $0 { subdomains.insert(item.id) } else { subdomains.remove(item.id) } }
                                ))
                            }
                            if !item.boost.stylesheet.isEmpty {
                                Text("Styles (anything that fetches from elsewhere was removed)").font(.caption).foregroundStyle(.secondary)
                                ScrollView {
                                    Text(Boosts.reviewText(item.boost.stylesheet).text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 90).border(Color.secondary.opacity(0.3))
                            }
                            if let script = item.script {
                                let shown = Boosts.reviewText(script)
                                Text("Script — \(script.utf8.count) bytes, \(script.split(whereSeparator: \.isNewline).count) lines")
                                    .font(.caption).foregroundStyle(.orange)
                                if shown.hidden > 0 {
                                    Text("Contains \(shown.hidden) invisible or control character\(shown.hidden == 1 ? "" : "s"), written out as \\u{…} below.")
                                        .font(.caption.bold()).foregroundStyle(.red)
                                }
                                ScrollView {
                                    Text(shown.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 260).border(Color.secondary.opacity(0.3))
                                Toggle("Allow this script", isOn: Binding(
                                    get: { allowed.contains(item.id) },
                                    set: { if $0 { allowed.insert(item.id) } else { allowed.remove(item.id) } }
                                ))
                            } else {
                                Text(item.boost.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(height: 480)
            HStack {
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
                Button("Bring In") {
                    Boosts.shared.commitImport(candidates, allowing: allowed, subdomains: subdomains)
                    done()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}

// MARK: - Settings

struct BoostsList: View {
    let browser: Browser
    @ObservedObject private var store = Boosts.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 6) {
                Pill("New…") { Boosts.edit(in: browser) }
                Pill("Import…") { importFile() }
                Pill("Export…") { exportFile() }.opacity(store.all.isEmpty ? 0.4 : 1).disabled(store.all.isEmpty)
            }
            ForEach(store.all) { boost in
                row(boost)
            }
        }
    }

    private func row(_ boost: Boost) -> some View {
        let tab = browser.active?.id
        let trying = tab.flatMap { store.trials[$0] } == boost.id
        return HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(boost.name.isEmpty ? boost.hosts.joined(separator: ", ") : boost.name).font(.system(size: 12.5)).lineLimit(1)
                Text(boost.summary).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            if boost.imported, let tab {
                if trying {
                    Pill("Keep", filled: true) { store.keep(boost.id); store.refresh(browser) }
                    Pill("Stop") { store.endTrial(tab: tab); store.refresh(browser) }
                } else {
                    Pill("Try") { store.tryOn(boost.id, tab: tab); store.refresh(browser) }
                }
            } else {
                Switch(on: Binding(get: { boost.enabled }, set: { store.setEnabled(boost.id, $0); store.refresh(browser) }))
            }
            Pill("Edit…") { BoostSheet.present(boost, browser: browser) }
            Pill("Delete", tint: .red) { store.remove(boost.id); store.refresh(browser) }
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Size first: nothing is read into memory from a file this large.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max
        guard size <= Boosts.maxImportFile else { browser.announce("That file is too large to be boosts"); return }
        guard let data = try? Data(contentsOf: url) else { return }
        let found = Boosts.parseImport(data)
        guard !found.isEmpty else { browser.announce("No boosts in that file"); return }
        BoostSheet.review(found, browser: browser)
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "boosts.json"
        guard panel.runModal() == .OK, let url = panel.url, let data = store.exportData() else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct BoostsPrivateSwitch: View {
    @State private var on = Boosts.allowsPrivate
    var body: some View {
        Switch(on: Binding(get: { on }, set: { on = $0; Boosts.allowsPrivate = $0 }))
    }
}
