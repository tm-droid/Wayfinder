//
//  JSONFile.swift
//  Wayfinder
//

import AppKit
import Foundation
import os

/// A Codable value stored as a JSON file in Application Support.
struct JSONFile<Value: Codable> {
    private static var logger: Logger { Logger(subsystem: "com.tanush.Wayfinder", category: "Storage") }

    let url: URL

    init(name: String) {
        let directory = URL.applicationSupportDirectory.appending(path: "Wayfinder", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: name)
    }

    init(url: URL) {
        self.url = url
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Nil when the file does not exist. Throws when it exists but cannot be read or decoded.
    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func write(_ value: Value) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    /// Renames the file to `<name>.corrupt-<timestamp>.json` so it is kept for recovery.
    func moveAside() {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent().appending(path: "\(name).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            Self.logger.error("Could not move aside \(url.lastPathComponent): \(error)")
        }
    }

    func save(_ value: Value) {
        do {
            try write(value)
        } catch {
            Self.logger.error("Could not write \(url.lastPathComponent): \(error)")
        }
    }
}

/// Coalesces bursts of changes into a single save.
final class SaveScheduler {
    private var pending: Task<Void, Never>?
    private var pendingSave: (() -> Void)?
    private let delay: Duration
    private var terminationObserver: (any NSObjectProtocol)?

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    deinit {
        terminationObserver.map(NotificationCenter.default.removeObserver)
    }

    func schedule(_ save: @escaping () -> Void) {
        pending?.cancel()
        pendingSave = save
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    /// Runs the waiting save now, if there is one.
    func flush() {
        pending?.cancel()
        pending = nil
        guard let save = pendingSave else { return }
        pendingSave = nil
        save()
    }
}
