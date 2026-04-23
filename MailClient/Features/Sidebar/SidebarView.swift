import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Editorial flow")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)

            Button {
                appState.isShowingCompose = true
            } label: {
                Label("Compose", systemImage: "square.and.pencil")
            }
            .buttonStyle(MailStreaPrimaryButtonStyle())
            .padding(.horizontal, 30)
            .padding(.top, 48)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        HStack(spacing: 14) {
                            Capsule()
                                .fill(appState.selectedSidebarItem == item ? AppTheme.textPrimary : Color.clear)
                                .frame(width: 4, height: 22)

                            Image(systemName: item.systemImageName)
                                .frame(width: 18)
                                .font(.system(size: 16, weight: .medium))

                            Text(item.rawValue)
                                .font(.system(size: 16, weight: .medium))

                            Spacer()
                        }
                        .foregroundStyle(appState.selectedSidebarItem == item ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(appState.selectedSidebarItem == item ? Color.white.opacity(0.92) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)

            Spacer()

            Divider()
                .overlay(AppTheme.panelBorder)
                .padding(.horizontal, 30)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 18) {
                SidebarFootnoteRow(title: "Settings", systemImage: "gearshape.fill")
                SidebarFootnoteRow(title: "Help", systemImage: "questionmark.circle.fill")
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
        }
        .background(AppTheme.panel)
    }
}

private struct SidebarFootnoteRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(AppTheme.textSecondary)
    }
}
