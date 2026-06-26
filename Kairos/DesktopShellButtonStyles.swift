import SwiftUI

enum ButtonSurfaceKind {
    case ghost
    case filled
    case outlined
    case secondary
    case modalSecondary
    case subButton
}

struct SurfaceButtonStyle: ButtonStyle {
    let kind: ButtonSurfaceKind
    var isActive = false
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        SurfaceButtonStyleBody(
            kind: kind,
            isActive: isActive,
            isPressed: configuration.isPressed,
            isDisabled: isDisabled,
            label: configuration.label
        )
    }
}

struct SurfaceButtonStyleBody<Label: View>: View {
    let kind: ButtonSurfaceKind
    let isActive: Bool
    let isPressed: Bool
    let isDisabled: Bool
    let label: Label

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var expandsLabel: Bool {
        switch kind {
        case .subButton:
            return true
        case .ghost, .filled, .outlined, .secondary, .modalSecondary:
            return false
        }
    }

    var body: some View {
        buttonSurface(
            kind: kind,
            isActive: isActive,
            isHovered: isHovered,
            isPressed: isPressed,
            isDisabled: isDisabled || !isEnabled
        ) {
            Group {
                if expandsLabel {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    label
                }
            }
            .font(DesktopShellTypography.labelMD)
            .foregroundStyle(DesktopShellTokens.actionPrimary)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

enum FoldedMenuSurfaceStyle {
    case ghost
    case outlined

    var surfacePadding: CGFloat {
        switch self {
        case .ghost:
            return DesktopShellTokens.componentGapXS
        case .outlined:
            return DesktopShellTokens.componentGapXS
        }
    }
}

struct FoldedMenuSurface<FixedContent: View, ScrollableContent: View>: View {
    let style: FoldedMenuSurfaceStyle
    var minWidth: CGFloat?
    var maxHeight: CGFloat?
    let fixedContent: FixedContent
    let scrollableContent: ScrollableContent

    @State private var fixedContentSize: CGSize = .zero
    @State private var scrollableContentSize: CGSize = .zero
    @State private var scrollViewportSize: CGSize = .zero
    @State private var scrollOffset: CGFloat = 0

    private let scrollCoordinateSpace = "FloatingDropdownScroll"

    init(
        style: FoldedMenuSurfaceStyle,
        minWidth: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        @ViewBuilder fixedContent: () -> FixedContent,
        @ViewBuilder scrollableContent: () -> ScrollableContent
    ) {
        self.style = style
        self.minWidth = minWidth
        self.maxHeight = maxHeight
        self.fixedContent = fixedContent()
        self.scrollableContent = scrollableContent()
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: DesktopShellTokens.radiusSurface,
            style: .continuous
        )
    }

    private var scrollableContentMaxHeight: CGFloat? {
        guard let maxHeight else {
            return nil
        }

        return max(
            maxHeight
                - fixedContentSize.height
                - (style.surfacePadding * 2)
                - DesktopShellTokens.componentGapXS,
            0
        )
    }

    private var needsScroll: Bool {
        guard let scrollableContentMaxHeight else {
            return false
        }

        return scrollableContentSize.height > scrollableContentMaxHeight + 0.5
    }

    private var canScrollDown: Bool {
        guard needsScroll else {
            return false
        }

        let remainingScroll = scrollableContentSize.height
            - scrollViewportSize.height
            - scrollOffset
        return remainingScroll > 1
    }

    @ViewBuilder
    private var scrollableStack: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.componentGapXS) {
            scrollableContent
        }
    }

    @ViewBuilder
    private var constrainedScrollableContent: some View {
        if let scrollableContentMaxHeight, needsScroll {
            ScrollView(.vertical, showsIndicators: false) {
                scrollableStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    scrollableContentSize = geometry.size
                                }
                                .onChange(of: geometry.size) { _, nextSize in
                                    scrollableContentSize = nextSize
                                }
                                .preference(
                                    key: DropdownScrollOffsetKey.self,
                                    value: -geometry.frame(
                                        in: .named(scrollCoordinateSpace)
                                    ).minY
                                )
                        }
                    }
            }
            .coordinateSpace(name: scrollCoordinateSpace)
            .frame(maxHeight: scrollableContentMaxHeight, alignment: .top)
            .captureSize($scrollViewportSize)
            .onPreferenceChange(DropdownScrollOffsetKey.self) { nextOffset in
                scrollOffset = nextOffset
            }
            .overlay(alignment: .bottom) {
                if canScrollDown {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        LinearGradient(
                            colors: [
                                DesktopShellTokens.backgroundModals.opacity(0),
                                DesktopShellTokens.backgroundModals
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 28)
                        .overlay(alignment: .bottom) {
                            KairosIconView(
                                icon: .chevronDown,
                                color: DesktopShellTokens.textTertiary
                            )
                            .frame(width: 16, height: 16)
                            .padding(.bottom, DesktopShellTokens.componentGapXS)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        } else {
            scrollableStack
                .captureSize($scrollableContentSize)
        }
    }

    @ViewBuilder
    private var shadowLayers: some View {
        ForEach(
            DesktopShellTokens.foldedMenuShadows.indices,
            id: \.self
        ) { index in
            let shadow = DesktopShellTokens.foldedMenuShadows[index]
            let inset = max(-shadow.spread, 0)

            RoundedRectangle(
                cornerRadius: max(
                    DesktopShellTokens.radiusSurface - inset,
                    0
                ),
                style: .continuous
            )
            .inset(by: inset)
            .fill(DesktopShellTokens.backgroundModals)
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.componentGapXS) {
            fixedContent
                .captureSize($fixedContentSize)

            constrainedScrollableContent
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .padding(style.surfacePadding)
        .background {
            surfaceShape
                .fill(DesktopShellTokens.backgroundModals)
        }
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(surfaceShape)
        .background {
            shadowLayers
        }
        .overlay {
            surfaceShape.stroke(
                DesktopShellTokens.borderStrong,
                lineWidth: DesktopShellTokens.borderWidth
            )
        }
    }
}
