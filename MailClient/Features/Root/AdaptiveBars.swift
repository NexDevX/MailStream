import SwiftUI

// MARK: - Sidebar toggle (medium-width regime)
//
// Shown above the message list at the medium breakpoint (840–1180). The
// user pins / unpins the sidebar with one click; the wide breakpoint
// always shows the sidebar, the narrow breakpoint never does, so this
// bar is only relevant in the middle.
struct SidebarToggleBar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(DS.Motion.surface) { isVisible.toggle() }
            } label: {
                DSIcon(name: .sidebar, size: 13)
                    .foregroundStyle(isVisible ? DS.Color.accent : DS.Color.ink3)
                    .frame(width: 26, height: 26)
                    .dsCard(cornerRadius: 5, fill: isVisible ? DS.Color.accentSoft : DS.Color.surface2, stroke: nil)
            }
            .buttonStyle(.plain)
            .help(isVisible
                  ? (appState.language == .simplifiedChinese ? "隐藏侧栏" : "Hide sidebar")
                  : (appState.language == .simplifiedChinese ? "显示侧栏" : "Show sidebar"))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(DS.Color.surface2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }
}

// MARK: - Drilldown top bar (narrow regime, list view)
//
// In drilldown mode the list view occupies the full window. There's no
// sidebar, so we replace it with a compact header that surfaces the
// folder name and a "compose" / settings shortcut.
struct DrilldownTopBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        appState.selectedSidebarItem = item
                    } label: {
                        if appState.selectedSidebarItem == item {
                            Label(item.title(in: appState.language), systemImage: "checkmark")
                        } else {
                            Text(item.title(in: appState.language))
                        }
                    }
                }
                Divider()
                Button(appState.strings.settings) { appState.route = .settings }
            } label: {
                HStack(spacing: 6) {
                    Text(appState.selectedSidebarItem.title(in: appState.language))
                        .font(DS.Font.sans(13, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                    DSIcon(name: .chevronDown, size: 10)
                        .foregroundStyle(DS.Color.ink4)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .dsCard(cornerRadius: 6, fill: DS.Color.surface2, stroke: nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Button { appState.openCompose() } label: {
                DSIcon(name: .pencil, size: 12)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Color.accent)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .compositingGroup()
            }
            .buttonStyle(.plain)
            .hoverLift()

            Button { appState.isShowingCommandPalette.toggle() } label: {
                DSIcon(name: .command, size: 12)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 28, height: 28)
                    .dsCard(cornerRadius: 6, fill: DS.Color.surface, stroke: DS.Color.line)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(DS.Color.surface2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }
}

// MARK: - Drilldown back bar (narrow regime, detail view)
//
// Replaces the empty space above the reading toolbar with an iOS-style
// "‹ Inbox" back affordance so the user can pop back to the list.
struct DrilldownBackBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(DS.Motion.surface) {
                    appState.isShowingDetailOverList = false
                }
            } label: {
                HStack(spacing: 4) {
                    DSIcon(name: .chevronLeft, size: 11)
                    Text(appState.selectedSidebarItem.title(in: appState.language))
                        .font(DS.Font.sans(12, weight: .medium))
                }
                .foregroundStyle(DS.Color.accent)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text(appState.selectionPositionText)
                .font(DS.Font.mono(11))
                .foregroundStyle(DS.Color.ink4)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(DS.Color.surface2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }
}
