import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            MessageListView()
        } detail: {
            MessageDetailView(message: appState.selectedMessage)
        }
        .sheet(isPresented: $appState.isShowingCompose) {
            ComposeView()
                .environmentObject(appState)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
