//
//  ContentBlocker.swift
//  Wayfinder
//

import CryptoKit
import Foundation
import Observation
import WebKit
import os

/// Compiles the bundled EasyList/EasyPrivacy rule lists and applies them to web views.
@MainActor
@Observable
final class ContentBlocker {
    static let shared = ContentBlocker()

    static let enabledKey = "contentBlockerEnabled"
    static let listNames = ["easylist", "easyprivacy"]
    private static let identifierPrefix = "wayfinder."
    nonisolated private static var logger: Logger { Logger(subsystem: "com.tanush.Wayfinder", category: "ContentBlocker") }

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Hosts where blocking is off. Subdomains are covered too.
    private(set) var allowlist: [String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let file: JSONFile<[String]>
    @ObservationIgnored private let store: WKContentRuleListStore?
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private var compiled: [WKContentRuleList]?
    @ObservationIgnored private var compiling: Task<[WKContentRuleList], Never>?

    /// Tests pass a temp-directory store; nil disables compilation.
    init(defaults: UserDefaults = .standard,
         file: JSONFile<[String]> = JSONFile(name: "BlockerAllowlist.json"),
         store: WKContentRuleListStore? = WKContentRuleListStore.default(),
         bundle: Bundle = .main) {
        self.defaults = defaults
        self.file = file
        self.store = store
        self.bundle = bundle
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        allowlist = file.load() ?? []
    }

    // MARK: Allowlist

    /// True if `host` equals an allowlisted host or is a subdomain of one.
    nonisolated static func isAllowlisted(host: String, in allowlist: [String]) -> Bool {
        let host = normalize(host)
        guard !host.isEmpty else { return false }
        return allowlist.contains { entry in
            let entry = normalize(entry)
            return !entry.isEmpty && (host == entry || host.hasSuffix("." + entry))
        }
    }

    nonisolated private static func normalize(_ host: String) -> String {
        var host = host.lowercased().trimmingCharacters(in: .whitespaces)
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    func isAllowlisted(_ host: String?) -> Bool {
        guard let host else { return false }
        return Self.isAllowlisted(host: host, in: allowlist)
    }

    func setAllowlisted(_ allowed: Bool, host: String) {
        let host = Self.normalize(host)
        guard !host.isEmpty else { return }
        if allowed {
            guard !allowlist.contains(host) else { return }
            allowlist.append(host)
        } else {
            // Removes the entry for this host or a parent domain covering it.
            allowlist.removeAll { Self.isAllowlisted(host: host, in: [$0]) }
        }
        file.save(allowlist)
    }

    // MARK: Compilation

    /// Compiled bundled lists, compiling on first use. Cached in the rule list store keyed by content hash.
    func rules() async -> [WKContentRuleList] {
        if let compiled { return compiled }
        if let compiling { return await compiling.value }
        let task = Task { await compileAll() }
        compiling = task
        let result = await task.value
        compiled = result
        compiling = nil
        return result
    }

    private func compileAll() async -> [WKContentRuleList] {
        guard let store else { return [] }
        var lists: [WKContentRuleList] = []
        var wanted: Set<String> = []
        for name in Self.listNames {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Blocklists")
                    ?? bundle.url(forResource: name, withExtension: "json") else {
                Self.logger.error("Missing bundled list \(name)")
                continue
            }
            guard let json = try? await Self.loadJSON(url) else { continue }
            let identifier = Self.identifierPrefix + name + "." + json.version
            wanted.insert(identifier)
            if let list = await Self.compile(json.text, identifier: identifier, in: store) {
                lists.append(list)
            }
        }
        // Drop stale versions of our lists.
        let available = await store.availableIdentifiers() ?? []
        for stale in available where stale.hasPrefix(Self.identifierPrefix) && !wanted.contains(stale) {
            try? await store.removeContentRuleList(forIdentifier: stale)
        }
        return lists
    }

    nonisolated private static func loadJSON(_ url: URL) async throws -> (text: String, version: String) {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            let version = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            return (String(decoding: data, as: UTF8.self), version)
        }.value
    }

    /// Looks up a compiled list, compiling and caching it on a miss.
    static func compile(_ json: String, identifier: String, in store: WKContentRuleListStore) async -> WKContentRuleList? {
        if let existing = try? await store.contentRuleList(forIdentifier: identifier) { return existing }
        do {
            return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
        } catch {
            logger.error("Could not compile \(identifier): \(error)")
            return nil
        }
    }

    // MARK: Applying

    /// Adds the rule lists to `controller` if blocking is on and `host` isn't allowlisted, else removes them.
    /// Safe to call repeatedly (e.g. on each navigation); lists are removed before being re-added.
    func apply(to controller: WKUserContentController, for host: String?) {
        if let compiled { compiled.forEach(controller.remove) }
        guard isEnabled, !isAllowlisted(host) else { return }
        if let compiled {
            compiled.forEach(controller.add)
            return
        }
        Task { [weak controller] in
            let lists = await rules()
            guard let controller, isEnabled, !isAllowlisted(host) else { return }
            lists.forEach(controller.remove)
            lists.forEach(controller.add)
        }
    }
}
