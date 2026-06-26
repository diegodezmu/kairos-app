import SwiftUI

enum DesktopShellTypography {
    // Figma type family is Inter (`type/family/base`). Use the installed Inter
    // family with explicit weights so the UI matches the design 1:1.
    private static func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        Font.custom("Inter", size: size).weight(weight)
    }

    static let wordmark = inter(13, .bold)
    static let titleMD = inter(18, .semibold)
    static let titleSM = inter(16, .semibold)
    static let bodyLG = inter(15, .regular)
    static let labelMD = inter(14, .medium)
    static let labelXS = inter(12, .semibold)
}

enum DesktopShellTokens {
    struct ShadowLayer {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let spread: CGFloat
    }

    // Figma MCP sources:
    // - shell nodes 83:8522, 88:27257, 91:38783
    // - toolbar 108:8183
    // - sidebar 99:6701
    // - button frames 72:2057, 74:2143, 121:6213, 78:1852
    // - toggle 75:2050
    // - status atoms 108:8044, 108:8650, 231:11155
    static let backgroundCanvas = Color(hex: 0x09090A)
    static let backgroundSurface = Color(hex: 0x0F0F10)
    static let backgroundElevated = Color(hex: 0x141517)
    static let backgroundModals = Color(hex: 0x1D1E22)
    static let backgroundModalsButton = Color(hex: 0x24262B)
    static let actionPrimary = Color(hex: 0xF5F7FA)
    static let actionSecondary = Color(hex: 0x24262B)
    static let actionSecondaryHover = Color(hex: 0x2F3238)
    static let actionAccent = Color(hex: 0xA96A2E)
    static let actionHighlight = Color(hex: 0x503219)
    static let textSecondary = Color(hex: 0xAEB8C4)
    static let textTertiary = Color(hex: 0x8792A0)
    static let borderSubtle = Color(hex: 0x24262B)
    static let borderStrong = Color(hex: 0x3D4148)
    static let borderDefault = Color(hex: 0x2F3238)
    static let statusSuccess = Color(hex: 0x43B973)
    static let statusDanger = Color(hex: 0xCA5256)
    static let shellCoordinateSpace = "DesktopShellCoordinateSpace"
    static let foldedMenuShadows = [
        ShadowLayer(
            color: Color(hex: 0x1D1E22, opacity: 0.1),
            radius: 4,
            x: 0,
            y: 2,
            spread: 0
        ),
        ShadowLayer(
            color: Color(hex: 0x1D1E22, opacity: 0.15),
            radius: 15,
            x: 0,
            y: 10,
            spread: -2
        ),
        ShadowLayer(
            color: Color(hex: 0x1D1E22, opacity: 0.1),
            radius: 6,
            x: 0,
            y: 0,
            spread: 0
        )
    ]

    static let toolbarHeight: CGFloat = 56
    static let toolbarTimeWidth: CGFloat = 74
    static let toolbarBPMWidth: CGFloat = 78
    static let toolbarSyncWidth: CGFloat = 146
    static let toolbarInfoWidth: CGFloat = toolbarTimeWidth + toolbarBPMWidth + toolbarSyncWidth + (componentGapLG * 2)
    static let sidebarWidth: CGFloat = 375
    static let sidebarOuterWidth: CGFloat = 391
    // Figma `component/panel/*-min-height` tokens — bounds for the vertical
    // Grid/Level resize split.
    static let gridPanelMinHeight: CGFloat = 128
    static let levelPanelMinHeight: CGFloat = 200
    // Figma `scroll-bar` thumb: 8 × 120, radius full, color/action/secondary.
    static let scrollThumbWidth: CGFloat = 8
    static let scrollThumbLength: CGFloat = 120
    // Interactive resize strip between Grid and Level. Wider than the 16px visual
    // gap so the splitter is comfortable to catch, but kept modest so it does not
    // swallow taps on the Grid's bottom step row (it sits above both panels).
    static let resizeDividerHitHeight: CGFloat = 28
    static let controlHeight: CGFloat = 32
    static let iconSize: CGFloat = 24
    static let statusDotSize: CGFloat = 8
    static let toggleWidth: CGFloat = 48
    static let toggleHeight: CGFloat = 28
    static let toggleThumbSize: CGFloat = 20

    static let radiusSurface: CGFloat = 8
    static let radiusElevated: CGFloat = 4
    static let radiusCanvas: CGFloat = 12
    static let borderWidth: CGFloat = 0.5

    static let componentGapXS: CGFloat = 4
    static let componentGapSM: CGFloat = 8
    static let componentGapMD: CGFloat = 12
    static let componentGapLG: CGFloat = 16
    static let componentGapXL: CGFloat = 24

    static let inputStatusGap: CGFloat = 12

    static let layoutGapSM: CGFloat = 8
    static let layoutGapLG: CGFloat = 16
    static let layoutGapXL: CGFloat = 24

    // Figma `component/button/ghost/max-width`.
    static let ghostButtonMaxWidth: CGFloat = 160
    static let ghostButtonTriggerTitleMaxWidth: CGFloat =
        ghostButtonMaxWidth
        - (componentGapSM * 2)
        - iconSize
        - componentGapXS
    static let ghostButtonFoldedHeaderTitleMaxWidth: CGFloat =
        ghostButtonMaxWidth
        - (componentGapXS * 2)
        - (componentGapSM * 2)
        - iconSize
        - componentGapXS
    static let ghostButtonFoldedItemTitleMaxWidth: CGFloat =
        ghostButtonMaxWidth
        - (componentGapXS * 2)
        - (componentGapSM * 2)

    static let latencyFieldWidth: CGFloat = 92
    static let latencyDragSensitivity: Double = 0.02
    static let latencyStep: Double = 0.01
}
