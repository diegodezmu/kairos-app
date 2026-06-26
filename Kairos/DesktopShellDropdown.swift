import Observation
import SwiftUI

@MainActor
@Observable
final class FloatingDropdownCoordinator {
    struct Presentation {
        let sourceID: UUID
        let frame: CGRect
        let style: FoldedMenuSurfaceStyle
        let minWidth: CGFloat?
        let fixedContent: AnyView
        let scrollableContent: AnyView
    }

    var presentation: Presentation?

    func toggle<FixedContent: View, ScrollableContent: View>(
        sourceID: UUID,
        frame: CGRect,
        style: FoldedMenuSurfaceStyle,
        minWidth: CGFloat? = nil,
        @ViewBuilder fixedContent: () -> FixedContent,
        @ViewBuilder scrollableContent: () -> ScrollableContent
    ) {
        if presentation?.sourceID == sourceID {
            dismiss()
            return
        }

        presentation = Presentation(
            sourceID: sourceID,
            frame: frame,
            style: style,
            minWidth: minWidth,
            fixedContent: AnyView(fixedContent()),
            scrollableContent: AnyView(scrollableContent())
        )
    }

    func dismiss() {
        presentation = nil
    }
}

struct FloatingDropdownOverlay: View {
    let presentation: FloatingDropdownCoordinator.Presentation
    let onDismiss: () -> Void

    @State private var popupSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let popupInset = presentation.style.surfacePadding
            let horizontalEdgeInset = DesktopShellTokens.componentGapSM
            let verticalEdgeInset = popupInset
            let originY = max(
                presentation.frame.minY - popupInset,
                verticalEdgeInset
            )
            let availableHeight = max(
                geometry.size.height - originY - verticalEdgeInset,
                DesktopShellTokens.controlHeight + (popupInset * 2)
            )
            let fallbackWidth = max(
                presentation.minWidth ?? presentation.frame.width,
                presentation.frame.width
            )
            let popupWidth = max(
                popupSize.width,
                fallbackWidth
            )
            let maxOriginX = max(
                horizontalEdgeInset,
                geometry.size.width - popupWidth - horizontalEdgeInset
            )
            let originX = min(
                max(
                    presentation.frame.minX - popupInset,
                    horizontalEdgeInset
                ),
                maxOriginX
            )

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                FoldedMenuSurface(
                    style: presentation.style,
                    minWidth: presentation.minWidth,
                    maxHeight: availableHeight
                ) {
                    presentation.fixedContent
                } scrollableContent: {
                    presentation.scrollableContent
                }
                .captureSize($popupSize)
                .offset(
                    x: originX,
                    y: originY
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DropdownScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FloatingDropdownCoordinatorKey: EnvironmentKey {
    static let defaultValue: FloatingDropdownCoordinator? = nil
}
