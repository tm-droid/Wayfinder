import SwiftUI

// Where a tab goes when it is let go, as in Arc: closed by the clock
// (Closing.swift) or by Clear. ⇧⌘T brings back the recent ones; this is the
// rest, thirty days of them, searched and reopened with a click. History has
// every page you visited, whether or not its tab was ever let go, and the
// recently-closed list is a few tabs in memory: neither says "this was
// tidied away", so this keeps its own short file. A private tab is never in
// it, and a page that is not a web address is not either.

@MainActor
final class Archive: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var url: URL
        var title: String
        var at: Date
    }

    /// A profile's file: Personal's is archive.json, as ever.
    nonisolated static func fileName(for profile: UUID) -> String {
        profile == Profile.personalID ? "archive.json" : "archive-\(profile.uuidString).json"
    }

    /// How long a tab stays in it.
    nonisolated static let keeps: TimeInterval = 30 * 24 * 3600
    /// And at most this many, the oldest first to go.
    nonisolated static let most = 2000

    let file: URL
    /// Newest first.
    @Published private(set) var entries: [Entry] = []

    init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Archive.pruned(Archive.cleaned(saved))
        }
    }

    /// Addresses without the credentials an older file may hold (see
    /// History.kept), the same page once.
    nonisolated static func cleaned(_ entries: [Entry]) -> [Entry] {
        var seen = Set<URL>()
        return entries.compactMap { entry in
            guard let url = History.kept(entry.url), seen.insert(url).inserted else { return nil }
            var entry = entry
            entry.url = url
            return entry
        }
    }

    /// Entries inside their thirty days and the cap, newest first.
    nonisolated static func pruned(_ entries: [Entry], now: Date = Date()) -> [Entry] {
        Array(entries.filter { now.timeIntervalSince($0.at) <= keeps }.sorted { $0.at > $1.at }.prefix(most))
    }

    /// What a search finds: every word in the title or the address.
    nonisolated static func matching(_ entries: [Entry], _ query: String) -> [Entry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let hay = (entry.title + " " + entry.url.absoluteString).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    /// A tab let go: kept unless it is private or not a web page. The same
    /// page again replaces its older line.
    func keep(_ tab: Tab, at now: Date = Date()) {
        guard !tab.shy, let address = tab.pending ?? tab.address,
              let scheme = address.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let url = History.kept(address)
        else { return }
        entries.removeAll { $0.url == url }
        entries.insert(Entry(url: url, title: tab.title, at: now), at: 0)
        entries = Archive.pruned(entries, now: now)
        save()
    }

    func forget(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Its profile deleted: emptied, its file removed, and nothing written again.
    func retire() {
        retired = true
        entries = []
        Disk.remove(file)
    }

    private var retired = false

    private func save() {
        guard !retired else { return }
        let list = entries, file = file
        Disk.write(file) { try? JSONEncoder().encode(list) }
    }
}

struct ArchivePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var archive: Archive
    @State private var hunt = ""
    @FocusState private var hunting: Bool

    var body: some View {
        let shown = Archive.matching(archive.entries, hunt)
        Plate("Archive", width: 600, close: { browser.putAway(.archive) }) {
            VStack(alignment: .leading, spacing: 14) {
                Hunt(text: $hunt, prompt: "Search tabs let go in the last 30 days", focus: $hunting)
                if shown.isEmpty {
                    Card { Nothing(hunt.isEmpty ? "Nothing yet. Tabs closed by the clock or by Clear wait here." : "Nothing matches.") }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { entry in
                                VStack(spacing: 0) {
                                    if entry.id != shown.first?.id { Rule() }
                                    Line(entry: entry, go: { browser.open(entry.url, foreground: true) },
                                         forget: { archive.forget(entry.id) })
                                }
                            }
                        }
                        .background(Palette.ground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    }
                    .listHeight(420)
                }
            }
        } foot: {
            HStack {
                Text(shown.count == 1 ? "1 tab" : "\(shown.count) tabs")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Pill("Clear archive") { withAnimation(Motion.settle) { archive.clear() } }
            }
        }
        .onAppear { hunting = true }
    }

    private struct Line: View {
        let entry: Archive.Entry
        let go: () -> Void
        let forget: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 12) {
                Mark(icon: Favicons.shared.cached(for: entry.url),
                     letter: entry.url.host()?.first.map { String($0).uppercased() } ?? "•", size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? Address.pretty(entry.url) : entry.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(Address.pretty(entry.url))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if hovering {
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                } else {
                    Text(When.said(entry.at))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: go)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}
