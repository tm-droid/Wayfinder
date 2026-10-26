//
//  BrowserWindow.swift
//  Wayfinder
//

import SwiftUI
import WebKit

struct BrowserWindow: View {
    @State private var model = BrowserWindowModel()

    var body: some View {
        NavigationSplitView {
            TabSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 360)
        } detail: {
            BrowserDetail(model: model)
        }
        .navigationTitle(model.selectedTab?.displayTitle ?? "Wayfinder")
        .toolbar(removing: .title)
        .focusedSceneValue(model)
        .background(WindowAccessor { model.window = $0 })
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct BrowserDetail: View {
    @Bindable var model: BrowserWindowModel

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        ZStack {
            if let tab = model.selectedTab {
                WebContainer(webView: tab.webView)

                if let error = tab.loadError {
                    ErrorPage(error: error, retry: tab.reload)
                } else if tab.showsStartPage {
                    StartPage(model: model)
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay(alignment: .top) {
            if model.address.showsSuggestions {
                SuggestionList(state: model.address) { suggestion in
                    model.commitAddress(suggestion.completion)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isFindBarVisible {
                FindBar(model: model)
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.isFindBarVisible)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                NavigationButtons(tab: model.selectedTab)
            }

            ToolbarItem(placement: .principal) {
                AddressBar(model: model, tab: model.selectedTab)
                    .frame(minWidth: 280, idealWidth: 620, maxWidth: 760)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if !downloads.items.isEmpty || model.isDownloadsPresented {
                    DownloadsButton(model: model)
                }
                Button {
                    model.newTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }
                .help("New Tab")
            }
        }
    }
}

private struct NavigationButtons: View {
    let tab: BrowserTab?

    var body: some View {
        Menu {
            if let tab {
                ForEach(tab.webView.backForwardList.backList.reversed(), id: \.self) { item in
                    historyButton(item, in: tab)
                }
            }
        } label: {
            Label("Back", systemImage: "chevron.left")
        } primaryAction: {
            tab?.goBack()
        }
        .menuIndicator(.hidden)
        .disabled(tab?.canGoBack != true)
        .help("Go back (hold for history)")

        Menu {
            if let tab {
                ForEach(tab.webView.backForwardList.forwardList, id: \.self) { item in
                    historyButton(item, in: tab)
                }
            }
        } label: {
            Label("Forward", systemImage: "chevron.right")
        } primaryAction: {
            tab?.goForward()
        }
        .menuIndicator(.hidden)
        .disabled(tab?.canGoForward != true)
        .help("Go forward (hold for history)")
    }

    private func historyButton(_ item: WKBackForwardListItem, in tab: BrowserTab) -> some View {
        Button {
            tab.go(to: item)
        } label: {
            Label {
                Text(item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.url.absoluteString)
            } icon: {
                SiteIcon(url: item.url)
            }
        }
    }
}
