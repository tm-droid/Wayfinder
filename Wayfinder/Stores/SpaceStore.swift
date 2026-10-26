//
//  SpaceStore.swift
//  Wayfinder
//

import Foundation
import Observation
import os
import SwiftUI
import WebKit

enum SpaceColor: String, Codable, CaseIterable {
    case blue, purple, pink, red, orange, yellow, green, gray
}

/// A workspace with its own tabs and its own WebKit profile (cookies, logins, storage).
struct Space: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// An emoji or an SF Symbol name.
    var icon = "square.grid.2x2"
    var color = SpaceColor.blue
    var dataStoreID = UUID()
    /// Uses WebKit's default data store, so logins from before spaces existed survive.
    var usesDefaultDataStore = false

    var dataStore: WKWebsiteDataStore {
        usesDefaultDataStore ? .default() : WKWebsiteDataStore(forIdentifier: dataStoreID)
    }
}

/// A group of pinned tabs. Folders can nest.
struct Folder: Codable, Identifiable, Hashable {
    var id = UUID()
    var spaceID: Space.ID
    var name: String
    var parentID: Folder.ID?
    var isCollapsed = false
}

/// A tab the browser remembers. Today tabs are only restored; essentials and pinned tabs are permanent.
struct TabRecord: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case essential, pinned, today
    }

    var id = UUID()
    var spaceID: Space.ID
    var url: URL?
    var title = ""
    var kind: Kind
    /// Only pinned tabs live in folders.
    var folderID: Folder.ID?
    /// The home URL an essential or pinned tab resets to when it is closed.
    var savedURL: URL?
    var interactionState: Data?
    var lastAccessedAt = Date.now
}

/// All spaces, folders and remembered tabs. Array order is display order within each section.
@Observable
final class SpaceStore {
    static let shared = SpaceStore()
    static let essentialsLimit = 12

    struct Snapshot: Codable {
        var spaces: [Space]
        var folders: [Folder]
        var records: [TabRecord]
    }

    private(set) var spaces: [Space]
    private(set) var folders: [Folder]
    private(set) var records: [TabRecord]

    @ObservationIgnored private static let logger = Logger(subsystem: "com.tanush.Wayfinder", category: "Storage")
    @ObservationIgnored private let file: JSONFile<Snapshot>
    @ObservationIgnored private let saver = SaveScheduler(delay: .milliseconds(200))

    init(file: JSONFile<Snapshot> = JSONFile(name: "Spaces.json"), defaults: UserDefaults = .standard) {
        self.file = file
        var snapshot: Snapshot?
        var isCorrupt = false
        do {
            snapshot = try file.read()
        } catch {
            Self.logger.error("Spaces.json is unreadable, moving it aside: \(error)")
            file.moveAside()
            isCorrupt = true
        }
        if let snapshot, !snapshot.spaces.isEmpty {
            spaces = snapshot.spaces
            folders = snapshot.folders
            records = snapshot.records
        } else {
            // First run with spaces: carry over the old session into a Space that keeps the existing cookies.
            let personal = Space(name: "Personal", icon: "person.crop.circle", usesDefaultDataStore: true)
            // A corrupt file means the old key may be stale, so only a missing file migrates.
            let urls = isCorrupt ? [] : (defaults.stringArray(forKey: PreferenceKey.savedTabs) ?? []).compactMap(URL.init(string:))
            let imported = urls.map { TabRecord(spaceID: personal.id, url: $0, kind: .today) }
            do {
                try file.write(Snapshot(spaces: [personal], folders: [], records: imported))
                if !isCorrupt { defaults.removeObject(forKey: PreferenceKey.savedTabs) }
            } catch {
                Self.logger.error("Could not write Spaces.json, keeping the old saved tabs: \(error)")
            }
            spaces = [personal]
            folders = []
            records = imported
        }
    }

    // MARK: Queries

    func space(_ id: Space.ID) -> Space? {
        spaces.first { $0.id == id }
    }

    func record(_ id: TabRecord.ID) -> TabRecord? {
        records.first { $0.id == id }
    }

    func records(in spaceID: Space.ID, kind: TabRecord.Kind) -> [TabRecord] {
        records.filter { $0.spaceID == spaceID && $0.kind == kind }
    }

    /// Essentials, then pinned, then today tabs.
    func records(in spaceID: Space.ID) -> [TabRecord] {
        [TabRecord.Kind.essential, .pinned, .today].flatMap { records(in: spaceID, kind: $0) }
    }

    func folders(in spaceID: Space.ID) -> [Folder] {
        folders.filter { $0.spaceID == spaceID }
    }

    // MARK: Spaces

    @discardableResult
    func addSpace(name: String, icon: String = "square.grid.2x2", color: SpaceColor = .blue) -> Space {
        let space = Space(name: name, icon: icon, color: color)
        spaces.append(space)
        scheduleSave()
        return space
    }

    /// Removes a space with its tabs and folders. The last space cannot be removed.
    @discardableResult
    func removeSpace(_ id: Space.ID) -> Bool {
        guard spaces.count > 1, spaces.contains(where: { $0.id == id }) else { return false }
        spaces.removeAll { $0.id == id }
        folders.removeAll { $0.spaceID == id }
        records.removeAll { $0.spaceID == id }
        scheduleSave()
        return true
    }

    func renameSpace(_ id: Space.ID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
        scheduleSave()
    }

    func updateSpace(_ id: Space.ID, name: String, icon: String, color: SpaceColor) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
        spaces[index].icon = icon
        spaces[index].color = color
        scheduleSave()
    }

    func moveSpaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        spaces.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    // MARK: Tabs

    /// Adds a record at the end, or right after `anchor`.
    func addRecord(_ record: TabRecord, after anchor: TabRecord.ID? = nil) {
        if let anchor, let index = records.firstIndex(where: { $0.id == anchor }) {
            records.insert(record, at: index + 1)
        } else {
            records.append(record)
        }
        scheduleSave()
    }

    func removeRecord(_ id: TabRecord.ID) {
        records.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Records the page a tab is showing. Non-web URLs are ignored.
    func update(_ id: TabRecord.ID, url: URL?, title: String) {
        mutate(id) {
            if let url, url.scheme == "http" || url.scheme == "https" {
                $0.url = url
                $0.title = title
            }
        }
    }

    func touch(_ id: TabRecord.ID) {
        mutate(id) { $0.lastAccessedAt = .now }
    }

    func setInteractionState(_ id: TabRecord.ID, _ state: Data?) {
        mutate(id) { $0.interactionState = state }
    }

    func pin(_ id: TabRecord.ID) {
        mutate(id) {
            if $0.kind != .pinned { $0.savedURL = $0.url }
            $0.kind = .pinned
            $0.folderID = nil
        }
    }

    func unpin(_ id: TabRecord.ID) {
        mutate(id) {
            $0.kind = .today
            $0.savedURL = nil
            $0.folderID = nil
        }
    }

    /// Returns false when the space already has `essentialsLimit` essentials.
    @discardableResult
    func makeEssential(_ id: TabRecord.ID) -> Bool {
        guard let record = record(id) else { return false }
        if record.kind == .essential { return true }
        guard records(in: record.spaceID, kind: .essential).count < Self.essentialsLimit else { return false }
        mutate(id) {
            $0.kind = .essential
            $0.savedURL = $0.url
            $0.folderID = nil
        }
        return true
    }

    /// Called when an essential or pinned tab is closed: the record stays and goes back to its home URL.
    func resetToSavedURL(_ id: TabRecord.ID) {
        mutate(id) {
            $0.url = $0.savedURL ?? $0.url
            $0.interactionState = nil
        }
    }

    /// Drops today tabs that will not be restored: all of them, or only those without a page.
    /// Records in `loaded` are open in a window and are never dropped.
    func discardTodayRecords(keepingRestorable: Bool, except loaded: Set<TabRecord.ID> = []) {
        records.removeAll {
            $0.kind == .today && !loaded.contains($0.id) && (!keepingRestorable || $0.url == nil)
        }
        scheduleSave()
    }

    /// Reorders `ids` among themselves. `ids` must be in their current display order, for example one section.
    func moveRecords(_ ids: [TabRecord.ID], fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = ids.compactMap { id in records.firstIndex { $0.id == id } }.sorted()
        guard slots.count == ids.count else { return }
        var moved = slots.map { records[$0] }
        moved.move(fromOffsets: source, toOffset: destination)
        for (slot, record) in zip(slots, moved) { records[slot] = record }
        scheduleSave()
    }

    // MARK: Folders

    @discardableResult
    func addFolder(name: String, in spaceID: Space.ID, parentID: Folder.ID? = nil) -> Folder {
        let folder = Folder(spaceID: spaceID, name: name, parentID: parentID)
        folders.append(folder)
        scheduleSave()
        return folder
    }

    func renameFolder(_ id: Folder.ID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
        scheduleSave()
    }

    /// Tabs in the folder move to the pinned root. Subfolders move up a level.
    func removeFolder(_ id: Folder.ID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        for index in records.indices where records[index].folderID == id { records[index].folderID = nil }
        for index in folders.indices where folders[index].parentID == id { folders[index].parentID = folder.parentID }
        folders.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Puts a tab in a folder of its own space, pinning it if needed, or back at the pinned root for nil.
    @discardableResult
    func moveRecord(_ id: TabRecord.ID, toFolder folderID: Folder.ID?) -> Bool {
        guard let record = record(id) else { return false }
        if let folderID {
            guard folders.contains(where: { $0.id == folderID && $0.spaceID == record.spaceID }) else { return false }
            if record.kind != .pinned { pin(id) }
        }
        mutate(id) { $0.folderID = folderID }
        return true
    }

    /// Moves a tab into a section (and folder, for pinned), before `anchor` or at the end.
    /// Returns false when the move is not allowed: essentials cap reached, unknown folder, or an anchor from another space.
    @discardableResult
    func place(_ id: TabRecord.ID, kind: TabRecord.Kind, folderID: Folder.ID? = nil, before anchor: TabRecord.ID? = nil) -> Bool {
        guard let record = record(id) else { return false }
        if let anchor, anchor != id, self.record(anchor)?.spaceID != record.spaceID { return false }
        switch kind {
        case .today:
            if record.kind != .today { unpin(id) }
        case .essential:
            guard makeEssential(id) else { return false }
        case .pinned:
            if let folderID, !folders.contains(where: { $0.id == folderID && $0.spaceID == record.spaceID }) { return false }
            if record.kind != .pinned { pin(id) }
            mutate(id) { $0.folderID = folderID }
        }
        guard let moved = records.firstIndex(where: { $0.id == id }) else { return true }
        let item = records.remove(at: moved)
        if let anchor, anchor != id, let target = records.firstIndex(where: { $0.id == anchor }) {
            records.insert(item, at: target)
        } else {
            records.append(item)
        }
        scheduleSave()
        return true
    }

    func setFolder(_ id: Folder.ID, isCollapsed: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isCollapsed = isCollapsed
        scheduleSave()
    }

    // MARK: Persistence

    /// Writes immediately instead of waiting for the save scheduler.
    func flush() {
        file.save(Snapshot(spaces: spaces, folders: folders, records: records))
    }

    private func mutate(_ id: TabRecord.ID, _ change: (inout TabRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        scheduleSave()
    }

    private func scheduleSave() {
        saver.schedule { [weak self] in
            self?.flush()
        }
    }
}
