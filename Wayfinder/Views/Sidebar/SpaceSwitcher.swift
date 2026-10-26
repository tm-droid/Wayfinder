//
//  SpaceSwitcher.swift
//  Wayfinder
//

import SwiftUI

/// The sidebar footer: one icon per space and a button to add one.
struct SpaceSwitcher: View {
    @Bindable var model: BrowserWindowModel

    @State private var isAdding = false
    @State private var editing: Space?
    @State private var deleting: Space?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.store.spaces) { space in
                let isSelected = space.id == model.selectedSpaceID
                SpaceIcon(icon: space.icon)
                    .frame(width: 28, height: 28)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(space.color.color.opacity(0.28))
                        }
                    }
                    .foregroundStyle(isSelected ? space.color.color : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectSpace(space.id) }
                    .help(space.name)
                    .accessibilityElement()
                    .accessibilityLabel(space.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { model.selectSpace(space.id) }
                    .contextMenu {
                        Button("Rename or Change Icon and Color…") { editing = space }
                        Divider()
                        Button("Delete Space…", role: .destructive) { deleting = space }
                            .disabled(model.store.spaces.count < 2)
                    }
            }

            Spacer(minLength: 0)

            Button {
                isAdding = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("New Space")
            .accessibilityLabel("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .sheet(isPresented: $isAdding) {
            SpaceEditSheet(space: nil) { name, icon, color in
                model.addSpace(name: name, icon: icon, color: color)
            }
        }
        .sheet(item: $editing) { space in
            SpaceEditSheet(space: space) { name, icon, color in
                model.store.updateSpace(space.id, name: name, icon: icon, color: color)
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "space")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { space in
            Button("Delete Space", role: .destructive) { model.removeSpace(space.id) }
        } message: { _ in
            Text("Its tabs, folders and website data (logins, cookies) will be removed. This cannot be undone.")
        }
    }
}

private struct SpaceEditSheet: View {
    let space: Space?
    let onSave: (String, String, SpaceColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "square.grid.2x2"
    @State private var color = SpaceColor.blue

    private static let symbols = [
        "square.grid.2x2", "person.crop.circle", "briefcase", "house", "graduationcap", "gamecontroller",
        "cart", "heart", "star", "book", "hammer", "paintbrush", "music.note", "airplane", "leaf", "flame",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(space == nil ? "New Space" : "Edit Space")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 8), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        SpaceIcon(icon: symbol)
                            .frame(width: 30, height: 30)
                            .background(icon == symbol ? color.color.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { icon = symbol }
                            .accessibilityLabel(symbol)
                    }
                }
                TextField("Or type an emoji", text: Binding(
                    get: { icon.allSatisfy(\.isASCII) ? "" : icon },
                    set: { if let first = $0.last { icon = String(first) } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(SpaceColor.allCases, id: \.self) { option in
                        Circle()
                            .fill(option.color)
                            .frame(width: 20, height: 20)
                            .overlay { if option == color { Circle().stroke(.primary, lineWidth: 2).padding(-3) } }
                            .contentShape(Circle())
                            .onTapGesture { color = option }
                            .accessibilityLabel(option.rawValue)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(space == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            guard let space else { return }
            name = space.name
            icon = space.icon
            color = space.color
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, icon, color)
        dismiss()
    }
}
