import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appState.strings.workspaceTitle)
                    .font(.system(size: AppTheme.sidebarTitleSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(appState.strings.workspaceSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Button {
                appState.isShowingCompose = true
            } label: {
                Label(appState.strings.compose, systemImage: "square.and.pencil")
            }
            .buttonStyle(MailStreaPrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        let isSelected = appState.selectedSidebarItem == item

                        HStack(spacing: 10) {
                            Image(systemName: item.systemImageName)
                                .frame(width: 17)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? AppTheme.focusAccent : AppTheme.textTertiary)

                            Text(item.title(in: appState.language))
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                            Spacer()

                            if isSelected {
                                Circle()
                                    .fill(AppTheme.focusAccent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? AppTheme.selectedCard : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? AppTheme.focusAccent.opacity(0.18) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)

            Spacer()

            Divider()
                .overlay(AppTheme.panelBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 9) {
                SidebarFootnoteRow(title: appState.strings.settings, systemImage: "gearshape.fill")
                SidebarFootnoteRow(title: appState.strings.help, systemImage: "questionmark.circle.fill")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
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
                .frame(width: 15)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(AppTheme.textTertiary)
    }
}
