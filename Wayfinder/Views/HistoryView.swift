//
//  HistoryView.swift
//  Wayfinder
//

import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var selection = Set<HistoryEntry.ID>()
    @State private var isConfirmingClear = false

    var body: some View {
        List(selection: $selection) {
            ForEach(sections, id: \.day) { section in
                Section(Self.title(for: section.day)) {
                    ForEach(section.entries) { entry in
                        HistoryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: HistoryEntry.ID.self) { ids in
            Button("Open") { open(ids) }
            Button("Open in New Tabs") { open(ids, inNewTabs: true) }
            Divider()
            Button("Delete", role: .destructive) { history.remove(ids) }
        } primaryAction: { ids in
            open(ids)
        }
        .onDeleteCommand { history.remove(selection) }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search History")
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("Pages you visit appear here."))
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                .disabled(history.entries.isEmpty)
        }
        .confirmationDialog("Clear all browsing history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("This removes every page from your history. It can’t be undone.")
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private var sections: [(day: Date, entries: [HistoryEntry])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let entries = query.isEmpty ? history.entries : history.entries.filter {
            $0.title.lowercased().contains(query) || $0.url.absoluteString.lowercased().contains(query)
        }
        let calendar = Calendar.current
        var result: [(day: Date, entries: [HistoryEntry])] = []
        for entry in entries.prefix(2000) {
            let day = calendar.startOfDay(for: entry.lastVisit)
            if result.last?.day == day {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append((day, [entry]))
            }
        }
        return result
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private func open(_ ids: Set<HistoryEntry.ID>, inNewTabs: Bool = false) {
        let urls = history.entries.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        if let window = BrowserWindowModel.frontmost {
            for (index, url) in urls.enumerated() {
                window.open(url, inNewTab: inNewTabs || index > 0)
            }
            window.window?.makeKeyAndOrderFront(nil)
        } else {
            BrowserWindowModel.pendingURLs = urls
            openWindow(id: WayfinderApp.browserWindowID)
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(url: entry.url)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .lineLimit(1)
                Text(entry.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(entry.lastVisit, format: .dateTime.hour().minute())
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
