import SwiftUI

struct ToolbarIconButton: View {
    let icon: KairosIcon
    // Retained for call-site clarity (which control is "on"); ghost styling never
    // uses it for a fill — the on-state is conveyed by the icon, not a blue background.
    var isActive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KairosIconView(
                icon: icon,
                color: isDisabled
                    ? DesktopShellTokens.textTertiary.opacity(0.5)
                    : DesktopShellTokens.actionPrimary
            )
            .frame(
                width: DesktopShellTokens.iconSize,
                height: DesktopShellTokens.iconSize
            )
        }
        .buttonStyle(
            SurfaceButtonStyle(
                kind: .ghost,
                isDisabled: isDisabled
            )
        )
        .disabled(isDisabled)
    }
}

struct PowerIconButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KairosIconView(
                icon: .power,
                color: DesktopShellTokens.actionPrimary
            )
            .frame(
                width: DesktopShellTokens.iconSize,
                height: DesktopShellTokens.iconSize
            )
        }
        .buttonStyle(
            SurfaceButtonStyle(
                kind: .filled,
                isActive: isOn
            )
        )
    }
}

struct ModeIconButton: View {
    let icon: KairosIcon
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KairosIconView(
                icon: icon,
                color: DesktopShellTokens.actionPrimary
            )
            .frame(
                width: DesktopShellTokens.iconSize,
                height: DesktopShellTokens.iconSize
            )
        }
        .buttonStyle(
            SurfaceButtonStyle(
                kind: .secondary,
                isActive: isSelected
            )
        )
    }
}

struct TertiaryIconButton: View {
    let icon: KairosIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KairosIconView(
                icon: icon,
                color: DesktopShellTokens.actionPrimary
            )
            .frame(
                width: DesktopShellTokens.iconSize,
                height: DesktopShellTokens.iconSize
            )
        }
        .buttonStyle(SurfaceButtonStyle(kind: .outlined))
    }
}

struct ToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)

                Circle()
                    .fill(DesktopShellTokens.actionPrimary)
                    .frame(width: DesktopShellTokens.toggleThumbSize, height: DesktopShellTokens.toggleThumbSize)
                    .padding(DesktopShellTokens.componentGapXS)
            }
            .frame(
                width: DesktopShellTokens.toggleWidth,
                height: DesktopShellTokens.toggleHeight
            )
        }
        .buttonStyle(.plain)
    }
}

struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SegmentButtonLabel(
                title: title,
                isSelected: isSelected,
                trailingIcon: trailingIcon
            )
        }
        .buttonStyle(.plain)
    }
}

struct SegmentMenuButton<Content: View>: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?
    let content: Content

    init(
        title: String,
        isSelected: Bool,
        trailingIcon: KairosIcon? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isSelected = isSelected
        self.trailingIcon = trailingIcon
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            SegmentButtonLabel(
                title: title,
                isSelected: isSelected,
                trailingIcon: trailingIcon
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}

struct USBSyncSegmentButton<Content: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    init(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            Button(action: action) {
                Text(title)
                    .font(DesktopShellTypography.labelMD)
                    .foregroundStyle(DesktopShellTokens.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesktopShellTokens.controlHeight)
            }
            .buttonStyle(.plain)

            Menu {
                content
            } label: {
                KairosIconView(
                    icon: .chevronDown,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
                .frame(minHeight: DesktopShellTokens.controlHeight)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .frame(maxWidth: .infinity, minHeight: DesktopShellTokens.controlHeight)
        .background(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .fill(isSelected ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)
        )
    }
}

struct SegmentButtonLabel: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            Text(title)
                .font(DesktopShellTypography.labelMD)
                .foregroundStyle(DesktopShellTokens.actionPrimary)

            if let trailingIcon {
                KairosIconView(
                    icon: trailingIcon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: DesktopShellTokens.controlHeight)
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .background(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .fill(isSelected ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)
        )
    }
}
