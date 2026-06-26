import SwiftUI

enum KairosIcon {
    case sidebar
    case sidebarFolded
    case play
    case stop
    case reset
    case metronomeDefault
    case metronomePing
    case metronomePong
    case power
    case link
    case chevronDown
    case doubleArrow
    case plus
    case minus
    case modeBlock
    case modeBorder
    case modeLine
    case modeCustom

    /// Asset-catalog image name. Vectors are exported verbatim from the Figma
    /// `Components` page (icon/* symbols) and stored as template SVGs.
    var assetName: String {
        switch self {
        case .sidebar: return "sidebar-unfolded"
        case .sidebarFolded: return "sidebar-folded"
        case .play: return "reproduce-play"
        case .stop: return "reproduce-stop"
        case .reset: return "reset"
        case .metronomeDefault: return "metronome-default"
        case .metronomePing: return "metronome-ping"
        case .metronomePong: return "metronome-pong"
        case .power: return "power"
        case .link: return "link"
        case .chevronDown: return "selector-fold"
        case .doubleArrow: return "double-arrow"
        case .plus: return "add"
        case .minus: return "remove"
        case .modeBlock: return "mode-solid"
        case .modeBorder: return "mode-border"
        case .modeLine: return "mode-line"
        case .modeCustom: return "mode-custom"
        }
    }
}

struct KairosIconView: View {
    let icon: KairosIcon
    let color: Color

    var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}
