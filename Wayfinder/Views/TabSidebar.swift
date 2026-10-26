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
    @AppStorage("sidebarWidth") private var sidebarWidth = 260.0

    @State private var slideOffset = 0.0
    @State private var contentOpacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 1) {
                    essentials
                    pinned
                    todayHeader
                    todayTabs
                    bookmarksSection
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .offset(x: slideOffset)
                .opacity(contentOpacity)
            }
            .scrollIndicators(.never)

            Divider()
            SpaceSwitcher(model: model)
        }
        .background {
            // Tint follows the space; low opacity keeps text readable in light and dark.
            LinearGradient(
                colors: [model.currentSpace.color.color.opacity(0.22), model.currentSpace.color.color.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: model.selectedSpaceID)
        }
        .background(SwipeCatcher { model.selectAdjacentSpace(offset: $0) })
        .onChange(of: model.selectedSpaceID) { old, new in slide(from: old, to: new) }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { sidebarWidth = $0 }
    }

    // MARK: Sections

    @ViewBuilder
    private var essentials: some View {
        let records = model.visibleRecords.filter { $0.kind == .essential }
        if !records.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 90), spacing: 6)], spacing: 6) {
                ForEach(records) { EssentialTile(model: model, record: $0) }
            }
            .padding(.bottom, 8)
            .tabDropTarget(model, kind: .essential)
        }
    }

    @ViewBuilder
    private var pinned: some View {
        let space = model.selectedSpaceID
        let rootFolders = model.store.folders(in: space).filter { $0.parentID == nil }
        let loose = model.visibleRecords.filter { $0.kind == .pinned && $0.folderID == nil }
        VStack(spacing: 1) {
            HStack {
                Text("Pinned")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.store.addFolder(name: "New Folder", in: space)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("New Folder")
                .accessibilityLabel("New Folder")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            ForEach(rootFolders) { FolderSection(model: model, folder: $0) }
            ForEach(loose) { SidebarTabRow(model: model, record: $0) }
            if rootFolders.isEmpty, loose.isEmpty {
                Text("Drag tabs here to pin them.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .tabDropTarget(model, kind: .pinned)
    }

    private var todayHeader: some View {
        HStack(spacing: 8) {
            VStack { Divider() }
            Button("Clear") { model.clearTodayTabs() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(model.todayTabs.isEmpty)
                .help("Close all tabs below the line")
                .accessibilityLabel("Clear today's tabs")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .tabDropTarget(model, kind: .today)
    }

    private var todayTabs: some View {
        VStack(spacing: 1) {
            Button {
                model.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(model.visibleRecords.filter { $0.kind == .today }) { SidebarTabRow(model: model, record: $0) }

            // Gives the empty space under the list room to accept drops.
            Color.clear.frame(height: 24)
        }
        .tabDropTarget(model, kind: .today)
    }

    private var bookmarksSection: some View {
        DisclosureGroup(isExpanded: $bookmarksExpanded) {
            ForEach(bookmarks.bookmarks) { bookmark in
                Button {
                    model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                } label: {
                    Label {
                        Text(bookmark.displayTitle).lineLimit(1)
                    } icon: {
                        SiteIcon(url: bookmark.url)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bookmark.url.absoluteString)
                .contextMenu {
                    Button("Open in New Tab") { model.open(bookmark.url, inNewTab: true) }
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
                    }
                    Divider()
                    Button("Delete Bookmark", role: .destructive) { bookmarks.remove(bookmark) }
                }
            }
            if bookmarks.bookmarks.isEmpty {
                Text("Press ⌘D to bookmark a page.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text("Bookmarks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    // MARK: Space switch animation

    private func slide(from old: Space.ID, to new: Space.ID) {
        let spaces = model.store.spaces
        guard let from = spaces.firstIndex(where: { $0.id == old }), let to = spaces.firstIndex(where: { $0.id == new }) else { return }
        let wrapped = abs(to - from) == spaces.count - 1 && spaces.count > 2
        let forward = wrapped ? to < from : to > from
        withTransaction(Transaction(animation: nil)) {
            slideOffset = forward ? 60 : -60
            contentOpacity = 0
        }
        withAnimation(.snappy(duration: 0.25)) {
            slideOffset = 0
            contentOpacity = 1
        }
    }
}
