//
//  SidebarSupport.swift
//  Wayfinder
//

import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What a sidebar drag carries: just the record id.
struct TabDragItem: Codable, Transferable {
    let id: TabRecord.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

extension SpaceColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .gray: .gray
        }
    }
}

/// A space's emoji or SF Symbol.
struct SpaceIcon: View {
    let icon: String
    var size: CGFloat = 15

    var body: some View {
        if icon.allSatisfy(\.isASCII) {
            Image(systemName: icon)
                .font(.system(size: size))
        } else {
            Text(icon)
                .font(.system(size: size))
        }
    }
}

/// Accepts dragged tabs. `before` places the tab ahead of that record, nil appends to the section.
struct TabDropTarget: ViewModifier {
    let model: BrowserWindowModel
    let kind: TabRecord.Kind
    var folderID: Folder.ID?
    var before: TabRecord.ID?
    var axis: Axis = .vertical

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: axis == .vertical ? .top : .leading) {
                if isTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: axis == .vertical ? nil : 2, height: axis == .vertical ? 2 : nil)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: TabDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                return model.place(item.id, kind: kind, folderID: folderID, before: before)
            } isTargeted: { isTargeted = $0 }
    }
}

extension View {
    func tabDropTarget(_ model: BrowserWindowModel, kind: TabRecord.Kind, folderID: Folder.ID? = nil,
                       before: TabRecord.ID? = nil, axis: Axis = .vertical) -> some View {
        modifier(TabDropTarget(model: model, kind: kind, folderID: folderID, before: before, axis: axis))
    }
}

/// Reports horizontal two-finger swipes over its area. Events are observed, never consumed.
struct SwipeCatcher: NSViewRepresentable {
    /// -1 for a swipe toward the previous space, 1 toward the next.
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? SwipeView)?.onSwipe = onSwipe
    }

    private final class SwipeView: NSView {
        var onSwipe: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var fired = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window, event.hasPreciseScrollingDeltas else { return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulated = 0
                fired = false
            }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point), !fired, event.momentumPhase.isEmpty else { return }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            accumulated += event.scrollingDeltaX
            if abs(accumulated) > 80 {
                fired = true
                // Content follows the fingers: swiping right shows the previous space.
                onSwipe?(accumulated > 0 ? -1 : 1)
                accumulated = 0
            }
        }
    }
}
