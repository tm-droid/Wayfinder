import Foundation

// What the user has done with mods, kept per profile: the mods they installed,
// which are on, their order, and each mod's preference values. The built-in
// mods are not stored; only their order, on/off and values are.
//
// The file is read defensively. One that is not JSON at all is set aside
// (Store.quarantine) and the state starts empty. Inside a readable file, each
// part is read on its own: an installed mod that no longer passes Mod.load is
// dropped, a value that its preference does not accept falls back to the
// default, and the rest stays. Writes are atomic.

struct ModState: Equatable {
    /// Installed from a file, in the order installed. Built-ins are not here.
    private(set) var installed: [Mod] = []
    /// Every mod id, built-in and installed, in the user's order.
    private(set) var order: [String] = []
    private(set) var enabled: Set<String> = []
    private(set) var values: [String: [String: ModPrefValue]] = [:]

    static let maxInstalled = 50
    static let version = 1

    init() { reconcile() }

    // MARK: - what there is

    var all: [Mod] { order.compactMap(mod) }

    func mod(_ id: String) -> Mod? {
        Mod.builtIns.first { $0.id == id } ?? installed.first { $0.id == id }
    }

    func isBuiltIn(_ id: String) -> Bool { Mod.builtIns.contains { $0.id == id } }
    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func value(of pref: ModPref, in mod: Mod) -> ModPrefValue {
        values[mod.id]?[pref.id].flatMap { pref.accepts($0) ? $0 : nil } ?? pref.defaultValue
    }

    /// The enabled mods in order, each with the flags its preferences leave.
    /// This is what gets merged into the look and the flags.
    var enabledMods: [Mod] {
        all.filter { enabled.contains($0.id) }.map { mod in
            var m = mod
            m.flags = mod.flags(with: values[mod.id] ?? [:])
            return m
        }
    }

    // MARK: - changes

    enum InstallProblem: Equatable {
        case builtInID
        case tooMany
        case invalid(Mod.LoadFailure)

        var message: String {
            switch self {
            case .builtInID: return "That id belongs to a mod that comes with Wayfinder."
            case .tooMany: return "You can install at most \(ModState.maxInstalled) mods. Remove one first."
            case .invalid(let failure): return failure.message
            }
        }
    }

    /// Adds `mod`, on; one with the same id is replaced in place and keeps its place, state and valid values.
    mutating func install(_ mod: Mod) -> InstallProblem? {
        let errors = mod.validate()
        if !errors.isEmpty { return .invalid(.invalid(errors)) }
        if isBuiltIn(mod.id) { return .builtInID }
        if let at = installed.firstIndex(where: { $0.id == mod.id }) {
            installed[at] = mod
            sanitizeValues(of: mod)
        } else {
            guard installed.count < ModState.maxInstalled else { return .tooMany }
            installed.append(mod)
            enabled.insert(mod.id)
            order.append(mod.id)
        }
        return nil
    }

    /// False for a built-in or an unknown id: those cannot be removed.
    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        guard let at = installed.firstIndex(where: { $0.id == id }) else { return false }
        installed.remove(at: at)
        order.removeAll { $0 == id }
        enabled.remove(id)
        values[id] = nil
        return true
    }

    mutating func setEnabled(_ id: String, _ on: Bool) {
        guard mod(id) != nil else { return }
        if on { enabled.insert(id) } else { enabled.remove(id) }
    }

    /// One place earlier (negative) or later; stops at the ends.
    mutating func move(_ id: String, by offset: Int) {
        guard let at = order.firstIndex(of: id) else { return }
        let to = min(max(at + offset, 0), order.count - 1)
        guard to != at else { return }
        order.insert(order.remove(at: at), at: to)
    }

    /// False if the mod or preference is unknown or the value does not fit it.
    @discardableResult
    mutating func setValue(_ value: ModPrefValue, pref: String, of id: String) -> Bool {
        guard let mod = mod(id), let p = mod.prefs.first(where: { $0.id == pref }), p.accepts(value) else { return false }
        values[id, default: [:]][pref] = value
        return true
    }

    private mutating func sanitizeValues(of mod: Mod) {
        guard var mine = values[mod.id] else { return }
        mine = mine.filter { key, value in mod.prefs.first { $0.id == key }?.accepts(value) == true }
        values[mod.id] = mine.isEmpty ? nil : mine
    }

    /// Order holds exactly the mods there are: unknown ids out, missing ones added (built-ins first).
    private mutating func reconcile() {
        let known = Mod.builtIns.map(\.id) + installed.map(\.id)
        var seen = Set<String>()
        order = order.filter { known.contains($0) && seen.insert($0).inserted }
        order += known.filter { !seen.contains($0) }
        enabled = enabled.filter(known.contains)
    }

    // MARK: - the file

    func encoded() -> Data? {
        struct File: Encodable {
            var version: Int
            var installed: [Mod]
            var order: [String]
            var enabled: [String]
            var values: [String: [String: ModPrefValue]]
        }
        let file = File(version: ModState.version, installed: installed, order: order,
                        enabled: order.filter(enabled.contains), values: values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(file)
    }

    /// Nil only when `data` is not a JSON object. Anything wrong inside it is dropped, not fatal.
    static func decode(_ data: Data) -> ModState? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var state = ModState()
        for item in (root["installed"] as? [Any]) ?? [] {
            guard state.installed.count < maxInstalled, item is [String: Any],
                  let bytes = try? JSONSerialization.data(withJSONObject: item),
                  case .success(let mod) = Mod.load(bytes),
                  !state.isBuiltIn(mod.id), !state.installed.contains(where: { $0.id == mod.id }) else { continue }
            state.installed.append(mod)
        }
        state.order = (root["order"] as? [Any])?.compactMap { $0 as? String } ?? []
        state.enabled = Set((root["enabled"] as? [Any])?.compactMap { $0 as? String } ?? [])
        if (root["enabled"] as? [Any]) == nil {
            // No record of what is on (a file from nowhere): installed mods are on, built-ins off, as at install.
            state.enabled = Set(state.installed.map(\.id))
        }
        state.reconcile()
        for (id, raw) in (root["values"] as? [String: Any]) ?? [:] {
            guard let mod = state.mod(id), let mine = raw as? [String: Any] else { continue }
            for pref in mod.prefs {
                // JSONSerialization hands Bool as NSNumber; telling it from a number needs its type.
                switch mine[pref.id] {
                case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
                    state.setValue(.on(n.boolValue), pref: pref.id, of: id)
                case let s as String:
                    state.setValue(.text(s), pref: pref.id, of: id)
                default: break
                }
            }
        }
        return state
    }

    /// The saved state at `url`. Missing: empty. Not JSON: set aside, empty.
    static func read(from url: URL) -> ModState {
        guard FileManager.default.fileExists(atPath: url.path) else { return ModState() }
        if let data = try? Data(contentsOf: url), let state = decode(data) { return state }
        Store.quarantine(url)
        return ModState()
    }

    /// Atomic. False if it could not be written.
    @discardableResult
    func write(to url: URL) -> Bool {
        guard let data = encoded() else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}

/// One profile's mods, shared by its windows. Every change is saved and announced.
@MainActor
final class ModStore: ObservableObject {
    /// Posted after any change, by any profile's store; windows redraw.
    static let changed = Notification.Name("ModStore.changed")

    private static var stores: [UUID: ModStore] = [:]

    static func shared(_ profile: UUID) -> ModStore {
        if let made = stores[profile] { return made }
        let made = ModStore(file: file(for: profile))
        stores[profile] = made
        return made
    }

    /// Personal's file is mods.json; another profile has its own.
    nonisolated static func file(for profile: UUID) -> URL {
        Store.file(profile == Profile.personalID ? "mods.json" : "mods-\(profile.uuidString).json")
    }

    let file: URL
    @Published private(set) var state: ModState

    init(file: URL) {
        self.file = file
        state = ModState.read(from: file)
    }

    func change(_ edit: (inout ModState) -> Void) {
        var next = state
        edit(&next)
        guard next != state else { return }
        state = next
        next.write(to: file)
        NotificationCenter.default.post(name: ModStore.changed, object: self)
    }

    /// Installs the manifest at `url`. The error is in plain words.
    func install(from url: URL) -> String? {
        switch ModStore.readManifest(at: url) {
        case .failure(let failure): return failure.message
        case .success(let mod):
            var problem: ModState.InstallProblem?
            change { problem = $0.install(mod) }
            return problem?.message
        }
    }

    /// A manifest from a file, reading no more than the cap plus a byte.
    nonisolated static func readManifest(at url: URL) -> Result<Mod, Mod.LoadFailure> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.unreadable("the file could not be opened")) }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Mod.maxManifestBytes + 1)) ?? Data()
        return Mod.load(data)
    }
}

/// Where the enabled mods come from: the user's, in their order, for a profile.
enum Mods {
    @MainActor static func enabled(profile: UUID = Profile.personalID) -> [Mod] {
        ModStore.shared(profile).state.enabledMods
    }
}
