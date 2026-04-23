import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            let layout = AppTheme.layout(for: geometry.size)

            VStack(spacing: 0) {
                ChromeBarView()

                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: layout.sidebarWidth)

                    Divider()

                    VStack(spacing: 0) {
                        ContentHeaderView()
                        Divider()

                        HSplitView {
                            MessageListView()
                                .frame(
                                    minWidth: layout.listMinWidth,
                                    idealWidth: layout.listIdealWidth,
                                    maxWidth: layout.listMaxWidth
                                )

                            MessageDetailView(message: appState.selectedMessage, layout: layout)
                                .frame(minWidth: layout.detailMinWidth)
                        }
                    }
                }
            }
            .background(AppTheme.canvas)
        }
        .sheet(isPresented: $appState.isShowingCompose) {
            ComposeView()
        }
    }
}

private struct ChromeBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            Text(appState.strings.appName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.chromeText)
                .padding(.leading, 72)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.chromeMuted)

                TextField(appState.strings.searchMail, text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.chromeText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 300)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.chromeField)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppTheme.chromeFieldBorder, lineWidth: 1)
            )
        }
        .frame(height: 52)
        .padding(.trailing, 16)
        .background(AppTheme.chrome)
    }
}

private struct ContentHeaderView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var filterSelectionNamespace

    var body: some View {
        HStack(spacing: 18) {
            Text(appState.strings.appName)
                .font(.system(size: AppTheme.titleFontSize, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            HStack(spacing: 2) {
                ForEach(InboxFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            appState.selectedInboxFilter = filter
                        }
                    } label: {
                        let isSelected = appState.selectedInboxFilter == filter

                        Text(filter.title(in: appState.language))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .frame(minWidth: 74)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.panelElevated)
                                        .matchedGeometryEffect(id: "filterSelection", in: filterSelectionNamespace)
                                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.panelMuted.opacity(0.86))
            )

            Spacer()

            HStack(spacing: 8) {
                TopBarIconButton(systemImage: "slider.horizontal.3")
                TopBarIconButton(systemImage: "person.crop.circle")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
