import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            let layout = AppTheme.layout(for: geometry.size)

            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: layout.sidebarWidth)

                        MessageListView()
                            .frame(
                                minWidth: layout.listMinWidth,
                                idealWidth: layout.listIdealWidth,
                                maxWidth: layout.listMaxWidth
                            )

                        MessageDetailView(
                            message: appState.selectedMessage,
                            layout: layout
                        )
                        .frame(minWidth: layout.detailMinWidth, maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)

                    StatusBarView()
                }
                .background(DS.Color.bg)

                if appState.isShowingCommandPalette {
                    CommandPaletteView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: appState.isShowingCommandPalette)
        }
        .sheet(isPresented: $appState.isShowingCompose) {
            ComposeView()
        }
    }
}
