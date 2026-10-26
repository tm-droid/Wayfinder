//
//  TabSidebar.swift
//  Wayfinder
//

import AppKit
import SwiftUI

struct TabSidebar: View {
    @Bindable var model: BrowserWindowModel

    @Environment(BookmarkStore.self) private var bookmarks
    @AppStorage("sidebarBookmarksExpanded") private var bookmarksExpanded = true

    var body: some View {
        List(selection: $model.selectedTabID) {
            if model.store.spaces.count > 1 {
                Picker("Space", selection: Binding(get: { model.selectedSpaceID }, set: model.selectSpace)) {
                    ForEach(model.store.spaces) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
            }

            ForEach([TabRecord.Kind.essential, .pinned], id: \.self) { kind in
                let records = model.visibleRecords.filter { $0.kind == kind }
                if !records.isEmpty {
                    Section(kind == .essential ? "Essentials" : "Pinned") {
                        ForEach(records) { record in
                            if let tab = model.tab(for: record) {
                                TabRow(tab: tab, isSelected: tab.id == model.selectedTabID) {
                                    model.close(tab)
                                }
                                .tag(tab.id)
                                .contextMenu { tabMenu(for: tab) }
                            } else {
                                // Unloaded: no web view until the user opens it.
                                Button {
                                    model.activate(record)
                                } label: {
                                    Label(record.title.isEmpty ? (record.savedURL.map(AddressInput.displayString(for:)) ?? "Tab") : record.title,
                                          systemImage: "pin")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(model.todayTabs) { tab in
                    TabRow(tab: tab, isSelected: tab.id == model.selectedTabID) {
                        model.close(tab)
                    }
                    .tag(tab.id)
                    .contextMenu { tabMenu(for: tab) }
                }
                .onMove(perform: model.moveTabs)

                Button {
                    model.newTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            } header: {
                Text("Tabs")
            }

            Section("Bookmarks", isExpanded: $bookmarksExpanded) {
                ForEach(bookmarks.bookmarks) { bookmark in
                    Button {
                        model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                    } label: {
                        Label {
                            Text(bookmark.displayTitle)
                                .lineLimit(1)
                        } icon: {
                            SiteIcon(url: bookmark.url)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .help(bookmark.url.absoluteString)
                    .contextMenu {
                        Button("Open in New Tab") { model.open(bookmark.url, inNewTab: true) }
                        Button("Copy Link") { copy(bookmark.url) }
                        Divider()
                        Button("Delete Bookmark", role: .destructive) { bookmarks.remove(bookmark) }
                    }
                }
                .onMove(perform: bookmarks.move)

                if bookmarks.bookmarks.isEmpty {
                    Text("Press ⌘D to bookmark a page.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func tabMenu(for tab: BrowserTab) -> some View {
        Button("Reload") { tab.reload() }
        Button("Duplicate") { model.duplicate(tab) }
        if model.store.record(tab.id)?.kind == .today {
            Button("Pin Tab") { model.pin(tab) }
            Button("Add to Essentials") { model.makeEssential(tab) }
        } else {
            Button("Unpin Tab") { model.unpin(tab) }
        }
        if let url = tab.url {
            Button("Copy Link") { copy(url) }
            Button(bookmarks.contains(url) ? "Remove Bookmark" : "Add Bookmark") {
                bookmarks.toggle(url: url, title: tab.title)
            }
        }
        Divider()
        Button("Close Tab") { model.close(tab) }
        Button("Close Other Tabs") { model.closeOtherTabs(except: tab) }
            .disabled(model.tabs.count < 2)
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

private struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if tab.isLoading && tab.estimatedProgress < 1 {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    SiteIcon(url: tab.url)
                }
            }
            .frame(width: 16, height: 16)

            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isHovering || isSelected {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close Tab")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(tab.url?.absoluteString ?? tab.displayTitle)
    }
}
