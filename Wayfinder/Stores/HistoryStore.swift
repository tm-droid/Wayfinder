//
//  HistoryStore.swift
//  Wayfinder
//

import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var title: String
    var lastVisit: Date
    var visitCount: Int

    var displayTitle: String {
        title.isEmpty ? AddressInput.displayString(for: url) : title
    }
}

@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private static let maximumEntries = 5000

    /// Newest first.
    private(set) var entries: [HistoryEntry]

    @ObservationIgnored private let file = JSONFile<[HistoryEntry]>(name: "History.json")
    @ObservationIgnored private let saver = SaveScheduler()

    init() {
        entries = file.load() ?? []
    }

    func recordVisit(url: URL, title: String) {
        guard Self.isRecordable(url) else { return }
        if let index = entries.firstIndex(where: { $0.url == url }) {
            var entry = entries.remove(at: index)
            entry.lastVisit = .now
            entry.visitCount += 1
            if !title.isEmpty { entry.title = title }
            entries.insert(entry, at: 0)
        } else {
            entries.insert(HistoryEntry(url: url, title: title, lastVisit: .now, visitCount: 1), at: 0)
            if entries.count > Self.maximumEntries {
                entries.removeLast(entries.count - Self.maximumEntries)
            }
        }
        scheduleSave()
    }

    func updateTitle(_ title: String, for url: URL) {
        guard !title.isEmpty, let index = entries.firstIndex(where: { $0.url == url }),
              entries[index].title != title else { return }
        entries[index].title = title
        scheduleSave()
    }

    func remove(_ ids: Set<HistoryEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    /// Entries matching the query, most visited and most recent first.
    func matches(for query: String, limit: Int) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let matching = entries.lazy.filter { entry in
            entry.url.absoluteString.lowercased().contains(query) || entry.title.lowercased().contains(query)
        }
        return Array(matching.prefix(200))
            .sorted { lhs, rhs in
                let lhsPrefix = Self.hostHasPrefix(lhs.url, query)
                let rhsPrefix = Self.hostHasPrefix(rhs.url, query)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.visitCount > rhs.visitCount
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Recent sites with one entry per host.
    func recentSites(limit: Int) -> [HistoryEntry] {
        var seenHosts = Set<String>()
        var result: [HistoryEntry] = []
        for entry in entries {
            let host = entry.url.host() ?? entry.url.absoluteString
            guard seenHosts.insert(host).inserted else { continue }
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    private static func isRecordable(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    private static func hostHasPrefix(_ url: URL, _ query: String) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return host.hasPrefix(query) || host.hasPrefix("www." + query)
    }

    private func scheduleSave() {
        saver.schedule { [weak self] in
            guard let self else { return }
            file.save(entries)
        }
    }
}
