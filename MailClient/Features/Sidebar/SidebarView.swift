import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.strings.workspaceTitle)
                    .font(.system(size: AppTheme.sidebarTitleSize, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(appState.strings.workspaceSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Button {
                appState.isShowingCompose = true
            } label: {
                Label(appState.strings.compose, systemImage: "square.and.pencil")
            }
            .buttonStyle(MailStreaPrimaryButtonStyle())
            .padding(.horizontal, 18)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        HStack(spacing: 9) {
                            Capsule()
                                .fill(appState.selectedSidebarItem == item ? AppTheme.textPrimary : Color.clear)
                                .frame(width: 2, height: 15)

                            Image(systemName: item.systemImageName)
                                .frame(width: 14)
                                .font(.system(size: 12, weight: .medium))

                            Text(item.title(in: appState.language))
                                .font(.system(size: 13, weight: .medium))

                            Spacer()
                        }
                        .foregroundStyle(appState.selectedSidebarItem == item ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(appState.selectedSidebarItem == item ? Color.white.opacity(0.92) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 20)

            Spacer()

            Divider()
                .overlay(AppTheme.panelBorder)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 10) {
                SidebarFootnoteRow(title: appState.strings.settings, systemImage: "gearshape.fill")
                SidebarFootnoteRow(title: appState.strings.help, systemImage: "questionmark.circle.fill")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(AppTheme.panel)
    }
}

private struct SidebarFootnoteRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(AppTheme.textSecondary)
    }
}
