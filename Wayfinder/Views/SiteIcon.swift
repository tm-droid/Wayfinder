//
//  SiteIcon.swift
//  Wayfinder
//

import SwiftUI

/// A site's favicon, or a colored monogram when it has none.
struct SiteIcon: View {
    let url: URL?
    var size: CGFloat = 16

    @Environment(FaviconLoader.self) private var favicons

    var body: some View {
        if let image = favicons.icon(for: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else if let host = url.flatMap({ AddressInput.displayString(for: $0) }), let letter = host.first {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Self.color(for: host).gradient)
                .frame(width: size, height: size)
                .overlay {
                    Text(String(letter).uppercased())
                        .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.85))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green, .mint, .cyan]

    private static func color(for host: String) -> Color {
        let hash = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}
