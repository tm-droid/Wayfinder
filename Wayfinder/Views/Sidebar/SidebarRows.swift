//
//  SidebarRows.swift
//  Wayfinder
//

import AppKit
import SwiftUI

private func displayTitle(_ record: TabRecord, _ tab: BrowserTab?) -> String {
    if let tab { return tab.displayTitle }
    if !record.title.isEmpty { return record.title }
    return (record.url ?? record.savedURL).map(AddressInput.displayString(for:)) ?? "New Tab"
}

/// The context menu shared by rows and essential tiles.
struct RecordMenu: View {
    let model: BrowserWindowModel
    let record: TabRecord

    @Environment(BookmarkStore.self) private var bookmarks

    private var tab: BrowserTab? { model.tab(for: record) }
    private var url: URL? { tab?.url ?? record.url }

    var body: some View {
        let store = model.store
        if record.kind == .today {
            Button("Pin Tab") { model.place(record.id, kind: .pinned) }
        } else {
            Button("Unpin Tab") { model.place(record.id, kind: .today) }
        }
        if record.kind == .essential {
            Button("Remove from Essentials") { model.place(record.id, kind: .pinned) }
        } else {
            Button("Add to Essentials") { model.place(record.id, kind: .essential) }
                .disabled(store.records(in: record.spaceID, kind: .essential).count >= SpaceStore.essentialsLimit)
        }

        let folders = store.folders(in: record.spaceID)
        Menu("Move to Folder") {
            ForEach(folders) { folder in
                Button(Self.path(of: folder, in: folders)) {
                    model.place(record.id, kind: .pinned, folderID: folder.id)
                }
                .disabled(record.folderID == folder.id)
            }
            if !folders.isEmpty { Divider() }
            Button("New Folder") {
                let folder = store.addFolder(name: "New Folder", in: record.spaceID)
                model.place(record.id, kind: .pinned, folderID: folder.id)
            }
        }

        if record.kind == .today, store.spaces.count > 1 {
            Menu("Move to Space") {
                ForEach(store.spaces.filter { $0.id != record.spaceID }) { space in
                    Button(space.name) {
                        if let tab { model.moveToSpace(tab, space.id) }
                    }
                    .disabled(tab == nil)
                }
            }
        }

        Divider()
        if let tab { Button("Reload") { tab.reload() } }
        Button("Duplicate") { model.newTab(url: url) }
            .disabled(url == nil)
        if let url {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            Button(bookmarks.contains(url) ? "Remove Bookmark" : "Add Bookmark") {
                bookmarks.toggle(url: url, title: displayTitle(record, tab))
            }
        }
        Divider()
        if let tab {
            Button(record.kind == .today ? "Close" : "Unload") { model.close(tab) }
        }
    }

    private static func path(of folder: Folder, in folders: [Folder]) -> String {
        var names = [folder.name]
        var parent = folder.parentID
        while let id = parent, let next = folders.first(where: { $0.id == id }), names.count < 8 {
            names.insert(next.name, at: 0)
            parent = next.parentID
        }
        return names.joined(separator: " / ")
    }
}

/// A full-width row for a pinned or today tab.
struct SidebarTabRow: View {
    let model: BrowserWindowModel
    let record: TabRecord
    var depth = 0

    @State private var isHovering = false

    var body: some View {
        let tab = model.tab(for: record)
        let isSelected = record.id == model.selectedTabID
        let isPinned = record.kind != .today
        HStack(spacing: 8) {
            Group {
                if let tab, tab.isLoading, tab.estimatedProgress < 1 {
                    ProgressView().controlSize(.mini)
                } else {
                    SiteIcon(url: tab?.url ?? record.url ?? record.savedURL)
                }
            }
            .frame(width: 16, height: 16)

            Text(displayTitle(record, tab))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if let tab, isHovering || isSelected {
                Button {
                    model.close(tab)
                } label: {
                    Image(systemName: isPinned ? "minus" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(isPinned ? "Unload Tab" : "Close Tab")
                .accessibilityLabel(isPinned ? "Unload Tab" : "Close Tab")
            }
        }
        .opacity(tab == nil ? 0.55 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : isHovering ? Color.primary.opacity(0.07) : .clear)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.activate(record) }
        .draggable(TabDragItem(id: record.id))
        .tabDropTarget(model, kind: record.kind, folderID: record.folderID, before: record.id)
        .contextMenu { RecordMenu(model: model, record: record) }
        .help((tab?.url ?? record.url)?.absoluteString ?? displayTitle(record, tab))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.activate(record) }
    }
}

/// A square favicon tile for an essential.
struct EssentialTile: View {
    let model: BrowserWindowModel
    let record: TabRecord

    @State private var isHovering = false

    var body: some View {
        let tab = model.tab(for: record)
        let isSelected = record.id == model.selectedTabID
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.18 : isHovering ? 0.12 : 0.07))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            if let tab, tab.isLoading, tab.estimatedProgress < 1 {
                ProgressView().controlSize(.small)
            } else {
                SiteIcon(url: tab?.url ?? record.url ?? record.savedURL, size: 24)
                    .opacity(tab == nil ? 0.45 : 1)
            }
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.activate(record) }
        .draggable(TabDragItem(id: record.id))
        .tabDropTarget(model, kind: .essential, before: record.id, axis: .horizontal)
        .contextMenu { RecordMenu(model: model, record: record) }
        .help(displayTitle(record, tab))
        .accessibilityElement()
        .accessibilityLabel(displayTitle(record, tab))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.activate(record) }
    }
}

/// A collapsible folder of pinned tabs and subfolders.
struct FolderSection: View {
    let model: BrowserWindowModel
    let folder: Folder
    var depth = 0

    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        let store = model.store
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(folder.isCollapsed ? 0 : 90))
                    .frame(width: 12)
                Image(systemName: folder.isCollapsed ? "folder" : "folder.fill")
                Text(folder.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .padding(.leading, CGFloat(depth) * 14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.2)) { store.setFolder(folder.id, isCollapsed: !folder.isCollapsed) }
            }
            .tabDropTarget(model, kind: .pinned, folderID: folder.id)
            .contextMenu {
                Button("Rename…") {
                    newName = folder.name
                    isRenaming = true
                }
                Button("New Subfolder") { store.addFolder(name: "New Folder", in: folder.spaceID, parentID: folder.id) }
                Divider()
                Button("Delete Folder", role: .destructive) { store.removeFolder(folder.id) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Folder \(folder.name), \(folder.isCollapsed ? "collapsed" : "expanded")")
            .accessibilityAddTraits(.isButton)

            if !folder.isCollapsed {
                ForEach(store.folders(in: folder.spaceID).filter { $0.parentID == folder.id }) { child in
                    FolderSection(model: model, folder: child, depth: depth + 1)
                }
                ForEach(model.visibleRecords.filter { $0.folderID == folder.id }) { record in
                    SidebarTabRow(model: model, record: record, depth: depth + 1)
                }
            }
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { store.renameFolder(folder.id, to: trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
