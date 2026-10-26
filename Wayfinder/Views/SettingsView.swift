//
//  SettingsView.swift
//  Wayfinder
//

import SwiftUI
import WebKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettings()
            }
        }
        .scenePadding()
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PreferenceKey.homepage) private var homepage = ""
    @AppStorage(PreferenceKey.searchEngine) private var searchEngine = SearchEngine.duckDuckGo
    @AppStorage(PreferenceKey.restoresTabs) private var restoresTabs = true

    var body: some View {
        Form {
            Picker("Search engine:", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.name).tag(engine)
                }
            }

            TextField("Homepage:", text: $homepage, prompt: Text("Start Page"))
            Text("New tabs open the homepage. Leave it empty to use the start page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Reopen tabs from last time", isOn: $restoresTabs)
        }
    }
}

private struct PrivacySettings: View {
    @Environment(HistoryStore.self) private var history

    @State private var isConfirming = false
    @State private var status: String?

    var body: some View {
        Form {
            LabeledContent("Website data:") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Clear History and Website Data…") { isConfirming = true }
                    Text(status ?? "Removes history, cookies, caches and site storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Clear history and website data?", isPresented: $isConfirming) {
            Button("Clear", role: .destructive) { clear() }
        } message: {
            Text("You’ll be signed out of websites. This can’t be undone.")
        }
    }

    private func clear() {
        history.clear()
        let store = WKWebsiteDataStore.default()
        Task {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            status = "History and website data cleared."
        }
    }
}
