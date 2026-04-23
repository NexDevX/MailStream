import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: AppTheme.sidebarWidth)

            Divider()

            VStack(spacing: 0) {
                TopBarView()
                Divider()

                HSplitView {
                    MessageListView()
                        .frame(minWidth: 420, idealWidth: AppTheme.listWidth, maxWidth: 560)

                    MessageDetailView(message: appState.selectedMessage)
                        .frame(minWidth: AppTheme.detailMinWidth)
                }
            }
        }
        .background(AppTheme.canvas)
        .sheet(isPresented: $appState.isShowingCompose) {
            ComposeView()
        }
    }
}

private struct TopBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 28) {
            Text("MailStrea")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 28) {
                ForEach(InboxFilter.allCases) { filter in
                    Button {
                        appState.selectedInboxFilter = filter
                    } label: {
                        VStack(spacing: 8) {
                            Text(filter.rawValue)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : AppTheme.textSecondary)

                            Rectangle()
                                .fill(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : Color.clear)
                                .frame(width: 42, height: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 18) {
                Image(systemName: "slider.horizontal.3")
                Image(systemName: "person.crop.circle")
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 22)
        .background(AppTheme.panel)
    }
}
