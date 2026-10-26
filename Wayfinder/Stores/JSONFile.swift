//
//  JSONFile.swift
//  Wayfinder
//

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

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    func save(_ value: Value) {
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Could not write \(url.lastPathComponent): \(error)")
        }
    }
}

/// Coalesces bursts of changes into a single save.
final class SaveScheduler {
    private var pending: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    func schedule(_ save: @escaping () -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            save()
        }
    }
}
