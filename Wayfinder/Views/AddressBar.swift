//
//  AddressBar.swift
//  Wayfinder
//

import AppKit
import SwiftUI

struct AddressBar: View {
    let model: BrowserWindowModel
    let tab: BrowserTab?

    @Environment(BookmarkStore.self) private var bookmarks
    @AppStorage(PreferenceKey.searchEngine) private var searchEngine = SearchEngine.duckDuckGo

    private var state: AddressFieldState { model.address }

    var body: some View {
        HStack(spacing: 6) {
            leadingIcon
                .frame(width: 16)

            AddressField(
                state: state,
                placeholder: "Search \(searchEngine.name) or enter website",
                displayText: tab?.url.map { AddressInput.displayString(for: $0) } ?? "",
                editingText: tab?.url?.absoluteString ?? "",
                focusRequest: model.addressFocusRequest,
                onSubmit: submit,
                onCancel: cancel
            )

            // Always in the hierarchy: adding or removing views in a toolbar item
            // re-hosts it, which would knock the field out of first responder.
            let showsPageButtons = tab?.url != nil && !state.isFocused
            HStack(spacing: 6) {
                bookmarkButton
                reloadButton
            }
            .opacity(showsPageButtons ? 1 : 0)
            .allowsHitTesting(showsPageButtons)
            .accessibilityHidden(!showsPageButtons)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.fill.tertiary, in: Capsule())
        .overlay(alignment: .bottom) { progressLine }
        .clipShape(Capsule())
        .onChange(of: tab?.id) { state.endEditing() }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if state.isFocused || tab?.url == nil {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
        } else if tab?.isSecure == true {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .help("This connection is secure.")
        } else if tab?.url?.scheme == "http" {
            Image(systemName: "lock.slash")
                .foregroundStyle(.orange)
                .help("This connection is not secure.")
        } else {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }

    private var bookmarkButton: some View {
        let isBookmarked = bookmarks.contains(tab?.url)
        return Button {
            if let tab, let url = tab.url { bookmarks.toggle(url: url, title: tab.title) }
        } label: {
            Image(systemName: isBookmarked ? "star.fill" : "star")
                .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(isBookmarked ? "Remove Bookmark" : "Add Bookmark")
    }

    private var reloadButton: some View {
        let isLoading = tab?.isLoading == true
        return Button {
            isLoading ? tab?.stopLoading() : tab?.reload()
        } label: {
            Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(isLoading ? "Stop" : "Reload")
    }

    @ViewBuilder
    private var progressLine: some View {
        if let tab, tab.isLoading {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0.08, tab.estimatedProgress), height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.easeOut(duration: 0.25), value: tab.estimatedProgress)
            }
            .allowsHitTesting(false)
        }
    }

    private func submit(_ text: String) {
        let input = state.highlightedSuggestion?.completion ?? text
        model.commitAddress(input)
    }

    private func cancel() {
        state.endEditing()
        model.focusWebView()
    }
}

/// The editable text of the address bar. An AppKit field, because SwiftUI focus
/// state does not reach text fields hosted in the window toolbar.
private struct AddressField: NSViewRepresentable {
    let state: AddressFieldState
    let placeholder: String
    /// Shown when not editing: the host.
    let displayText: String
    /// Shown when the field takes focus: the full URL.
    let editingText: String
    let focusRequest: Int
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusReportingTextField {
        let field = FocusReportingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onFocus = { [weak coordinator = context.coordinator] field in coordinator?.didFocus(field) }
        field.onBlur = { [weak coordinator = context.coordinator] field in coordinator?.didBlur(field) }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusReportingTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.currentEditor() == nil {
            field.alignment = state.isFocused ? .left : .center
        }

        if !state.isFocused && field.stringValue != displayText {
            field.stringValue = displayText
        }

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            // A new window's sidebar claims focus as it appears, so ask again shortly after.
            for delay in [0.0, 0.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard focusRequest == context.coordinator.lastFocusRequest, !field.isFirstResponder else { return }
                    field.window?.makeFirstResponder(field)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        var lastFocusRequest = 0

        init(_ parent: AddressField) {
            self.parent = parent
        }

        func didFocus(_ field: NSTextField) {
            let text = parent.editingText
            field.alignment = .left
            field.stringValue = text
            parent.state.text = text
            parent.state.isFocused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.state.userDidType(field.stringValue)
        }

        func didBlur(_ field: NSTextField) {
            parent.state.isFocused = false
            parent.state.endEditing()
            field.alignment = .center
            field.stringValue = parent.displayText
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard parent.state.showsSuggestions else { return false }
                parent.state.moveHighlight(by: 1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard parent.state.showsSuggestions else { return false }
                parent.state.moveHighlight(by: -1)
                return true
            default:
                return false
            }
        }
    }
}

final class FocusReportingTextField: NSTextField {
    var onFocus: ((NSTextField) -> Void)?
    /// Called when focus moves elsewhere, even if editing never started.
    var onBlur: ((NSTextField) -> Void)?

    private var firstResponderObservation: NSKeyValueObservation?
    private var hasFocus = false

    var isFirstResponder: Bool {
        guard let editor = window?.firstResponder as? NSTextView else { return false }
        return editor.isFieldEditor && editor.delegate === self
    }

    override func becomeFirstResponder() -> Bool {
        // Alignment and text must change before the field editor attaches:
        // changing alignment while editing aborts the edit.
        onFocus?(self)
        let accepted = super.becomeFirstResponder()
        if accepted {
            hasFocus = true
            currentEditor()?.selectAll(nil)
        }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.hasFocus, !self.isFirstResponder else { return }
                self.hasFocus = false
                self.onBlur?(self)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let wasEditing = currentEditor() != nil
        super.mouseDown(with: event)
        // The first click selects the whole address, like Safari.
        if !wasEditing {
            currentEditor()?.selectAll(nil)
        }
    }
}

/// The dropdown under the address bar.
struct SuggestionList: View {
    let state: AddressFieldState
    let pick: (Suggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionRow(suggestion: suggestion, isHighlighted: index == state.highlightedIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(suggestion) }
                    .onHover { hovering in
                        if hovering { state.highlightedIndex = index }
                    }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.5))
        }
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16, height: 16)
            Text(suggestion.title)
                .lineLimit(1)
            Text(suggestion.subtitle)
                .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch suggestion.kind {
        case .search:
            Image(systemName: "magnifyingglass")
        case .website:
            Image(systemName: "globe")
        case .bookmark, .history:
            SiteIcon(url: suggestion.url)
        }
    }
}
