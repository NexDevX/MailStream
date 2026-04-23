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
                        .frame(minWidth: 308, idealWidth: AppTheme.listWidth, maxWidth: AppTheme.listMaxWidth)

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
        HStack(spacing: 14) {
            Text(appState.strings.appName)
                .font(.system(size: AppTheme.titleFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                ForEach(InboxFilter.allCases) { filter in
                    Button {
                        appState.selectedInboxFilter = filter
                    } label: {
                        Text(filter.title(in: appState.language))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(appState.selectedInboxFilter == filter ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(appState.selectedInboxFilter == filter ? AppTheme.panelElevated : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.panelMuted.opacity(0.72))
            )

            Spacer()

            HStack(spacing: 8) {
                TopBarIconButton(systemImage: "slider.horizontal.3")
                TopBarIconButton(systemImage: "person.crop.circle")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AppTheme.panel)
    }
}

private struct TopBarIconButton: View {
    let systemImage: String

    var body: some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.panelMuted.opacity(0.72))
                )
        }
        .buttonStyle(.plain)
    }
}
