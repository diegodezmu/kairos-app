import SwiftUI

struct SidebarCardSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            Text(title)
                .font(DesktopShellTypography.titleSM)
                .foregroundStyle(DesktopShellTokens.textSecondary)

            content
        }
        // Match the Grid/Level cards: each subsection owns 16px vertical padding so
        // the gap to the divider (subsection 16 + container 8) is the same 24px.
        .padding(.vertical, DesktopShellTokens.layoutGapLG)
    }
}

struct SidebarDivider: View {
    var body: some View {
        // Figma sidebar divider: `color/border/default` (#2F3238) at 0.5px.
        // A plain `Divider()` renders the system separator color, so draw the
        // hairline explicitly to match the design token exactly.
        Rectangle()
            .fill(DesktopShellTokens.borderDefault)
            .frame(height: DesktopShellTokens.borderWidth)
            .frame(maxWidth: .infinity)
    }
}

struct SidebarValueRow<Control: View>: View {
    let label: String
    let control: Control

    init(
        label: String,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: DesktopShellTokens.layoutGapSM) {
            Text(label)
                .font(DesktopShellTypography.bodyLG)
                .foregroundStyle(DesktopShellTokens.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
    }
}

struct DataAtomView: View {
    let text: String
    var width: CGFloat
    var isDisabled = false

    var body: some View {
        Text(text)
            .font(DesktopShellTypography.labelXS)
            .monospacedDigit()
            .foregroundStyle(DesktopShellTokens.textTertiary)
            .opacity(isDisabled ? 0.55 : 1)
            // Figma `data` atoms are single-line (`whitespace-nowrap`). The fixed
            // width keeps the right info cluster from drifting as digits change;
            // lineLimit + minimumScaleFactor guarantee one line without wrapping.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, DesktopShellTokens.componentGapXS)
            .padding(.horizontal, DesktopShellTokens.componentGapXS)
            .frame(width: width, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SyncStatusView: View {
    let descriptor: SyncStatusDescriptor
    var compact = true

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            if descriptor.showsLinkIcon {
                KairosIconView(
                    icon: .link,
                    color: descriptor.tone.color
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }

            Text(descriptor.text)
                .font(DesktopShellTypography.labelXS)
                .foregroundStyle(DesktopShellTokens.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .padding(.vertical, DesktopShellTokens.componentGapXS)
        .padding(.horizontal, compact ? DesktopShellTokens.componentGapXS : 0)
    }
}

struct InputStatusView<Status: SidebarInputStatusDescriptor>: View {
    let status: Status

    var body: some View {
        guard status.sidebarStatusTone != .hidden else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: DesktopShellTokens.componentGapSM) {
                Circle()
                    .fill(statusColor)
                    .frame(width: DesktopShellTokens.statusDotSize, height: DesktopShellTokens.statusDotSize)

                Text(status.sidebarStatusLabel)
                    .font(DesktopShellTypography.labelXS)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
                    .lineLimit(1)
            }
        )
    }

    private var statusColor: Color {
        switch status.sidebarStatusTone {
        case .hidden:
            return .clear
        case .waiting:
            return DesktopShellTokens.actionPrimary
        case .connected:
            return DesktopShellTokens.statusSuccess
        case .disconnected:
            return DesktopShellTokens.statusDanger
        }
    }
}
