//
//  BrowserImporter.swift
//  Wayfinder
//
//  Entry point: sniff file content and dispatch to the matching parser.
//

import Foundation

enum BrowserImporter {
    static func detectAndParse(fileURL: URL) throws -> ImportedData {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { throw ImportError.unreadable }
        return try detectAndParse(data: data)
    }

    static func detectAndParse(data: Data) throws -> ImportedData {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if ArcImporter.looksLikeArc(json) { return ArcImporter.parse(json: json) }
            if ChromeImporter.looksLikeChrome(json) { return ChromeImporter.parse(json: json) }
            throw ImportError.unrecognizedFormat
        }
        return try SafariImporter.parse(data: data)
    }
}
