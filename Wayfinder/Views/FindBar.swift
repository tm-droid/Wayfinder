//
//  FindBar.swift
//  Wayfinder
//

import SwiftUI

struct FindBar: View {
    @Bindable var model: BrowserWindowModel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find on Page", text: $model.findText)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($isFocused)
                .onSubmit { model.findNext() }

            if model.findHasNoMatches {
                Text("Not found")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            ControlGroup {
                Button {
                    model.findNext(backwards: true)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Previous Match")

                Button {
                    model.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Next Match")
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(model.findText.isEmpty)

            Button("Done") { model.hideFindBar() }
                .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: Capsule())
        .onExitCommand { model.hideFindBar() }
        .onChange(of: model.findText) { model.findNext() }
        .onChange(of: model.findFocusRequest, initial: true) { isFocused = true }
    }
}
