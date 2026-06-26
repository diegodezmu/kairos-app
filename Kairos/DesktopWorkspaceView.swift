import AppKit
import SwiftUI

struct DesktopWorkspaceSplitMetrics: Equatable {
    let availableHeight: CGFloat
    let gap: CGFloat
    let contentHeight: CGFloat
    let gridHeight: CGFloat
    let levelHeight: CGFloat
    let dividerCenterY: CGFloat

    init(
        availableHeight: CGFloat,
        gridFraction: Double,
        liveGridHeight: CGFloat?,
        gap: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) {
        let resolvedAvailableHeight = max(availableHeight, 1)
        let resolvedGap = max(gap, 0)
        let resolvedContentHeight = max(resolvedAvailableHeight - resolvedGap, 1)
        let proposedGridHeight = liveGridHeight
            ?? resolvedContentHeight * CGFloat(gridFraction)
        let resolvedGridHeight = Self.clampGridHeight(
            proposedGridHeight,
            contentHeight: resolvedContentHeight,
            gridMinHeight: gridMinHeight,
            levelMinHeight: levelMinHeight
        )

        self.availableHeight = resolvedAvailableHeight
        self.gap = resolvedGap
        self.contentHeight = resolvedContentHeight
        self.gridHeight = resolvedGridHeight
        self.levelHeight = max(resolvedContentHeight - resolvedGridHeight, 1)
        self.dividerCenterY = resolvedGridHeight + (resolvedGap / 2)
    }

    static func clampGridHeight(
        _ proposed: CGFloat,
        contentHeight: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) -> CGFloat {
        let resolvedContentHeight = max(contentHeight, 1)
        let lowerBound = max(gridMinHeight, 0)
        let upperBound = resolvedContentHeight - max(levelMinHeight, 0)

        guard lowerBound <= upperBound else {
            return min(
                max(proposed, resolvedContentHeight * 0.25),
                resolvedContentHeight * 0.75
            )
        }

        return min(max(proposed, lowerBound), upperBound)
    }

    static func normalizedGridFraction(
        gridHeight: CGFloat,
        contentHeight: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) -> Double {
        let resolvedContentHeight = max(contentHeight, 1)
        let resolvedGridHeight = clampGridHeight(
            gridHeight,
            contentHeight: resolvedContentHeight,
            gridMinHeight: gridMinHeight,
            levelMinHeight: levelMinHeight
        )
        return Double(resolvedGridHeight / resolvedContentHeight)
    }
}

struct DesktopWorkspaceLiveView: View {
    let model: DesktopShellModel

    /// Fraction of the available height assigned to the Grid panel when Grid and
    /// Level are stacked. Persisted across launches; clamped by the Figma panel
    /// min-height tokens (`component/panel/grid-min-height` = 128,
    /// `component/panel/level-min-height` = 200).
    @AppStorage("kairos.workspace.gridFraction") private var gridFraction: Double = 0.66
    /// Grid height captured the moment a resize drag begins. The drag is measured
    /// against this fixed baseline (plus the cursor delta) so the split tracks the
    /// pointer 1:1 instead of compounding as the divider repositions.
    @State private var dragStartGridHeight: CGFloat?
    /// Live Grid height while a drag is in flight. Driving the drag through a
    /// transient @State — instead of writing @AppStorage on every frame — keeps the
    /// motion smooth and persists the fraction only once, on release.
    @State private var liveGridHeight: CGFloat?

    var body: some View {
        // The split layout and the resize divider live OUTSIDE the per-renderer
        // TimelineViews so the drag gesture is not cancelled by the 30 fps redraw
        // that drives the meters. Each surface owns its own TimelineView for the
        // live content.
        GeometryReader { geometry in
            let gap = DesktopShellTokens.layoutGapLG
            let gridMinHeight = DesktopShellTokens.gridPanelMinHeight
            let levelMinHeight = DesktopShellTokens.levelPanelMinHeight
            let splitMetrics = DesktopWorkspaceSplitMetrics(
                availableHeight: geometry.size.height,
                gridFraction: gridFraction,
                liveGridHeight: liveGridHeight,
                gap: gap,
                gridMinHeight: gridMinHeight,
                levelMinHeight: levelMinHeight
            )

            Group {
                if model.settings.isGridVisible, model.settings.isLevelVisible {
                    ZStack(alignment: .topLeading) {
                        gridSurface
                            .frame(
                                width: geometry.size.width,
                                height: splitMetrics.gridHeight,
                                alignment: .topLeading
                            )

                        levelSplitSurface
                            .frame(
                                width: geometry.size.width,
                                height: splitMetrics.levelHeight,
                                alignment: .topLeading
                            )
                            .offset(y: splitMetrics.gridHeight + splitMetrics.gap)

                        WorkspaceResizeDivider(
                            width: geometry.size.width,
                            centerY: splitMetrics.dividerCenterY,
                            onChanged: { delta in
                                let base = dragStartGridHeight ?? splitMetrics.gridHeight
                                liveGridHeight = DesktopWorkspaceSplitMetrics.clampGridHeight(
                                    base + delta,
                                    contentHeight: splitMetrics.contentHeight,
                                    gridMinHeight: gridMinHeight,
                                    levelMinHeight: levelMinHeight
                                )
                            },
                            onBegan: {
                                // Capture the baseline the instant the drag
                                // starts, so the first delta is measured from
                                // exactly here.
                                dragStartGridHeight = splitMetrics.gridHeight
                                liveGridHeight = splitMetrics.gridHeight
                            },
                            onEnded: {
                                if let live = liveGridHeight {
                                    gridFraction = DesktopWorkspaceSplitMetrics
                                        .normalizedGridFraction(
                                            gridHeight: live,
                                            contentHeight: splitMetrics.contentHeight,
                                            gridMinHeight: gridMinHeight,
                                            levelMinHeight: levelMinHeight
                                        )
                                }
                                liveGridHeight = nil
                                dragStartGridHeight = nil
                            }
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .topLeading
                        )
                        .zIndex(1)
                    }
                } else if model.settings.isGridVisible {
                    gridSurface
                        .frame(maxHeight: .infinity)
                } else if model.settings.isLevelVisible {
                    levelExpandedSurface
                        .frame(maxHeight: .infinity)
                } else {
                    emptyState
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridSurface: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.gridFrame.cycles.isEmpty,
                emptyTitle: "Enable a cycle to preview Grid."
            ) {
                GridRenderer(
                    frame: snapshot.gridFrame,
                    onStepTap: { slot, stepIndex in
                        model.cycleCustomStepMode(slot: slot, stepIndex: stepIndex)
                    }
                )
            }
        }
    }

    private var levelSplitSurface: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.levelSplitFrame.lanes.isEmpty,
                emptyTitle: "Enable a window to preview Level."
            ) {
                LevelRenderer(frame: snapshot.levelSplitFrame)
            }
        }
    }

    private var levelExpandedSurface: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.levelExpandedFrame.lanes.isEmpty,
                emptyTitle: "Enable a window to preview Level."
            ) {
                LevelRenderer(frame: snapshot.levelExpandedFrame)
            }
        }
    }

    private var emptyState: some View {
        RoundedRectangle(
            cornerRadius: DesktopShellTokens.radiusCanvas,
            style: .continuous
        )
        .fill(DesktopShellTokens.backgroundSurface)
        .overlay {
            Text("Enable Grid or Level from the sidebar.")
                .font(DesktopShellTypography.bodyLG)
                .foregroundStyle(DesktopShellTokens.textTertiary)
        }
    }
}

/// Splitter between the Grid and Level surfaces.
///
/// The interactive layer is an AppKit `NSView` (`ResizeHandleRepresentable`)
/// rather than a SwiftUI gesture, because a professional splitter needs two
/// guarantees SwiftUI gestures do not give reliably:
///   1. A resize cursor that always appears and never sticks — driven by an
///      `NSTrackingArea` `cursorUpdate`, the same mechanism AppKit uses for its
///      own divider cursors.
///   2. A drag that cannot be lost on fast pointer moves — native `mouseDown` →
///      `mouseDragged` → `mouseUp` get automatic mouse capture, so every event
///      is delivered to the handle until the button is released.
///
/// The handle is transparent; the visible grabber is drawn in SwiftUI beneath it
/// and brightens on hover/drag. The drag delta is measured against the pointer
/// position captured at `mouseDown` (in window coordinates), so it tracks the
/// cursor 1:1 and never feeds back as the divider repositions during the resize.
struct WorkspaceResizeDivider: View {
    let width: CGFloat
    let centerY: CGFloat
    /// Reports the baseline-relative drag distance in points (positive = drag
    /// down, i.e. grow Grid), measured from the `mouseDown` location.
    let onChanged: (CGFloat) -> Void
    /// Fires once at `mouseDown`, before any movement, so the parent can capture
    /// the Grid height baseline with zero delta (no jump at drag start).
    let onBegan: () -> Void
    let onEnded: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Subtle grabber: invisible at rest, brightening while the pointer
            // is over the strip or a resize is in flight.
            Capsule(style: .continuous)
                .fill(DesktopShellTokens.textTertiary)
                .frame(width: 36, height: 4)
                .opacity(isHovering || isDragging ? 0.9 : 0)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: isDragging)
                .position(x: width / 2, y: centerY)
                .allowsHitTesting(false)

            ResizeHandleRepresentable(
                onHoverChange: { isHovering = $0 },
                onBegan: {
                    isDragging = true
                    onBegan()
                },
                onChanged: onChanged,
                onEnded: {
                    isDragging = false
                    onEnded()
                }
            )
            .frame(
                width: width,
                height: DesktopShellTokens.resizeDividerHitHeight
            )
            .position(x: width / 2, y: centerY)
        }
    }
}

/// AppKit-backed splitter handle. Owns the resize cursor and the drag loop; see
/// `WorkspaceResizeDivider` for why this is native rather than a SwiftUI gesture.
struct ResizeHandleRepresentable: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.apply(onHoverChange: onHoverChange, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.apply(onHoverChange: onHoverChange, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    final class HandleView: NSView {
        private var onHoverChange: ((Bool) -> Void)?
        private var onBegan: (() -> Void)?
        private var onChanged: ((CGFloat) -> Void)?
        private var onEnded: (() -> Void)?
        private var isDragging = false

        /// Pointer Y (window coordinates) captured at `mouseDown`. Window space
        /// has its origin at the bottom-left with Y increasing upward, so a
        /// downward drag lowers Y — hence the `start - current` delta below maps a
        /// downward drag to a positive value (grow Grid).
        private var dragStartY: CGFloat = 0

        func apply(
            onHoverChange: @escaping (Bool) -> Void,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onHoverChange = onHoverChange
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        // Let the splitter respond on the first click even when the window is not
        // yet key, matching native desktop-app behaviour.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        // Rebuild the tracking area whenever the handle's geometry changes (the
        // divider moves continuously while resizing), so the cursor region always
        // matches the live bounds. `.inVisibleRect` keeps it pinned to `bounds`.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.cursorUpdate, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            guard !isDragging else {
                return
            }
            onHoverChange?(false)
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            dragStartY = event.locationInWindow.y
            NSCursor.resizeUpDown.set()
            onHoverChange?(true)
            onBegan?()
        }

        override func mouseDragged(with event: NSEvent) {
            // Keep asserting the cursor for the duration of the drag, including
            // when the pointer runs past a clamp limit and off the handle.
            NSCursor.resizeUpDown.set()
            onChanged?(dragStartY - event.locationInWindow.y)
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
            onEnded?()
            let location = convert(event.locationInWindow, from: nil)
            onHoverChange?(bounds.contains(location))
        }
    }
}

struct RendererSurface<Content: View>: View {
    let hasContent: Bool
    let emptyTitle: String
    let content: Content

    init(
        hasContent: Bool,
        emptyTitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.hasContent = hasContent
        self.emptyTitle = emptyTitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            if hasContent {
                content
            } else {
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
                .fill(DesktopShellTokens.backgroundSurface)

                Text(emptyTitle)
                    .font(DesktopShellTypography.bodyLG)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
        )
    }
}
