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
                        .frame(minWidth: 316, idealWidth: AppTheme.listWidth, maxWidth: AppTheme.listMaxWidth)

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
        HStack(spacing: 24) {
            Text(appState.strings.appName)
                .font(.system(size: AppTheme.titleFontSize, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 24) {
                ForEach(InboxFilter.allCases) { filter in
                    Button {
                        appState.selectedInboxFilter = filter
                    } label: {
                        VStack(spacing: 6) {
                            Text(filter.title(in: appState.language))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : AppTheme.textSecondary)

                            Rectangle()
                                .fill(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : Color.clear)
                                .frame(width: 38, height: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                Image(systemName: "person.crop.circle")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(AppTheme.panel)
    }
}
