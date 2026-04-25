import SwiftUI

/// Thin footer matching the design canvas — sync status, counts, ⌘K hint.
struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                if appState.isRefreshingMailbox {
                    PulseRing(color: DS.Color.accent, size: 6)
                } else {
                    Circle()
                        .fill(DS.Color.green)
                        .frame(width: 6, height: 6)
                }
                Text("\(appState.accounts.count)/\(appState.accounts.count) 已同步")
                    .contentTransition(.numericText())
            }
            .animation(DS.Motion.surface, value: appState.isRefreshingMailbox)
            dot
            Text("上次 2 分钟前")
            Spacer()
            Text("\(appState.messages.count) \(appState.strings.messagesUnit)")
                .contentTransition(.numericText())
            dot
            Text("\(appState.unreadCount) \(appState.strings.unreadWord)")
                .foregroundStyle(DS.Color.accent)
                .contentTransition(.numericText())
            dot
            Button {
                appState.isShowingCommandPalette.toggle()
            } label: {
                HStack(spacing: 4) {
                    Kbd(text: "⌘K")
                    Text(appState.strings.commandPalette)
                }
            }
            .buttonStyle(.plain)
        }
        .font(DS.Font.mono(10))
        .foregroundStyle(DS.Color.ink3)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(DS.Color.surface2)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }

    private var dot: some View {
        Text("·").foregroundStyle(DS.Color.ink5)
    }
}
