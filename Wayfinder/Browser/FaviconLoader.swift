//
//  FaviconLoader.swift
//  Wayfinder
//

import AppKit
import Observation

/// Fetches site icons and caches them in memory and on disk, keyed by host.
@Observable
final class FaviconLoader {
    static let shared = FaviconLoader()

    /// Bumped whenever a download adds an icon, so views re-read the cache.
    private var revision = 0

    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var inFlight: [String: Task<NSImage?, Never>] = [:]
    @ObservationIgnored private var failedHosts = Set<String>()
    @ObservationIgnored private let directory: URL

    init() {
        directory = URL.cachesDirectory.appending(path: "Favicons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The cached icon for the site, loading it in the background if needed.
    func icon(for url: URL?) -> NSImage? {
        _ = revision
        guard let host = url?.host() else { return nil }
        if let icon = icons[host] { return icon }
        if let icon = NSImage(contentsOf: fileURL(for: host)) {
            icons[host] = icon
            return icon
        }
        if let url, inFlight[host] == nil, !failedHosts.contains(host) {
            Task { await load(for: url, candidates: []) }
        }
        return nil
    }

    /// Downloads the first candidate that decodes, falling back to /favicon.ico.
    @discardableResult
    func load(for pageURL: URL, candidates: [URL]) async -> NSImage? {
        guard let host = pageURL.host() else { return nil }
        if let task = inFlight[host] { return await task.value }

        var urls = candidates
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL, !urls.contains(fallback) {
            urls.append(fallback)
        }

        let task = Task<NSImage?, Never> {
            for url in urls {
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                      let image = NSImage(data: data), image.isValid else { continue }
                return image
            }
            return nil
        }
        inFlight[host] = task
        let image = await task.value
        inFlight[host] = nil

        if let image {
            icons[host] = image
            failedHosts.remove(host)
            revision += 1
            save(image, for: host)
        } else if icons[host] == nil {
            failedHosts.insert(host)
        }
        return image ?? icons[host]
    }

    private func fileURL(for host: String) -> URL {
        directory.appending(path: host + ".png")
    }

    private func save(_ image: NSImage, for host: String) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: fileURL(for: host), options: .atomic)
    }
}
