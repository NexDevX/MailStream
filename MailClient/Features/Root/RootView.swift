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
                        .frame(minWidth: 286, idealWidth: AppTheme.listWidth, maxWidth: AppTheme.listMaxWidth)

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
        HStack(spacing: 18) {
            Text(appState.strings.appName)
                .font(.system(size: AppTheme.titleFontSize, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 18) {
                ForEach(InboxFilter.allCases) { filter in
                    Button {
                        appState.selectedInboxFilter = filter
                    } label: {
                        VStack(spacing: 4) {
                            Text(filter.title(in: appState.language))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : AppTheme.textSecondary)

                            Rectangle()
                                .fill(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : Color.clear)
                                .frame(width: 30, height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                Image(systemName: "person.crop.circle")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(AppTheme.panel)
    }
}
