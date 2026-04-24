import SwiftUI

/// Design-canvas icon set mapped to SF Symbols.
///
/// Names mirror `docs/Design/mailstream/icons.jsx` so view code can stay close
/// to the design source. Sizes are unified around 14pt with stroke weight .light.
enum DSIconName: String {
    case inbox, star, send, draft, archive, trash, search, pencil
    case reply, replyAll, forward, more, plus, close, filter, tag
    case paperclip, clock, bell, check, chevronDown, chevronLeft, chevronRight
    case settings, help, user, at, mail, pin, bold, italic, link, list
    case command, arrowRight, arrowUp, arrowDown
    case flame, bookmark, circleCheck, dot, bolt, sparkle, grid, layers, shield, bar, x
    case sidebar, refresh, folder, userPlus, download, moon, sun, eye

    var systemName: String {
        switch self {
        case .inbox:        return "tray"
        case .star:         return "star"
        case .send:         return "paperplane"
        case .draft:        return "doc"
        case .archive:      return "archivebox"
        case .trash:        return "trash"
        case .search:       return "magnifyingglass"
        case .pencil:       return "pencil"
        case .reply:        return "arrowshape.turn.up.left"
        case .replyAll:     return "arrowshape.turn.up.left.2"
        case .forward:      return "arrowshape.turn.up.right"
        case .more:         return "ellipsis"
        case .plus:         return "plus"
        case .close, .x:    return "xmark"
        case .filter:       return "line.3.horizontal.decrease"
        case .tag:          return "tag"
        case .paperclip:    return "paperclip"
        case .clock:        return "clock"
        case .bell:         return "bell"
        case .check:        return "checkmark"
        case .chevronDown:  return "chevron.down"
        case .chevronLeft:  return "chevron.left"
        case .chevronRight: return "chevron.right"
        case .settings:     return "gearshape"
        case .help:         return "questionmark.circle"
        case .user:         return "person"
        case .at:           return "at"
        case .mail:         return "envelope"
        case .pin:          return "pin"
        case .bold:         return "bold"
        case .italic:       return "italic"
        case .link:         return "link"
        case .list:         return "list.bullet"
        case .command:      return "command"
        case .arrowRight:   return "arrow.right"
        case .arrowUp:      return "arrow.up"
        case .arrowDown:    return "arrow.down"
        case .flame:        return "flame"
        case .bookmark:     return "bookmark"
        case .circleCheck:  return "checkmark.circle"
        case .dot:          return "circle.fill"
        case .bolt:         return "bolt"
        case .sparkle:      return "sparkles"
        case .grid:         return "square.grid.2x2"
        case .layers:       return "square.3.layers.3d"
        case .shield:       return "checkmark.shield"
        case .bar:          return "chart.bar"
        case .sidebar:      return "sidebar.left"
        case .refresh:      return "arrow.clockwise"
        case .folder:       return "folder"
        case .userPlus:     return "person.badge.plus"
        case .download:     return "arrow.down.to.line"
        case .moon:         return "moon"
        case .sun:          return "sun.max"
        case .eye:          return "eye"
        }
    }
}

struct DSIcon: View {
    let name: DSIconName
    var size: CGFloat = 14
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: name.systemName)
            .font(.system(size: size, weight: weight))
            .frame(width: size + 2, height: size + 2)
    }
}
