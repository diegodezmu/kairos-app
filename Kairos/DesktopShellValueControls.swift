import SwiftUI

struct RenameableTitle: View {
    let title: String
    let onCommit: (String) -> Void

    @State private var isPresented = false
    @State private var draftName = ""

    var body: some View {
        Text(title)
            .font(DesktopShellTypography.titleSM)
            .foregroundStyle(DesktopShellTokens.textSecondary)
            .contextMenu {
                Button("Rename") {
                    draftName = title
                    isPresented = true
                }
            }
            .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename")
                        .font(DesktopShellTypography.titleSM)

                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            isPresented = false
                        }
                        Button("Apply") {
                            onCommit(draftName)
                            isPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
            }
    }
}

struct MenuValueButton<Content: View>: View {
    let title: String
    let icon: KairosIcon
    var width: CGFloat?
    var maxTitleWidth: CGFloat?
    let content: (@escaping () -> Void) -> Content

    @Environment(\.floatingDropdownCoordinator) private var dropdownCoordinator
    @State private var dropdownID = UUID()
    @State private var triggerFrame: CGRect = .zero
    @State private var triggerWidth: CGFloat = 0

    init(
        title: String,
        icon: KairosIcon,
        width: CGFloat? = nil,
        maxTitleWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.title = title
        self.icon = icon
        self.width = width
        self.maxTitleWidth = maxTitleWidth
        self.content = content
    }

    var body: some View {
        triggerButton
            .captureFrame(
                in: .named(DesktopShellTokens.shellCoordinateSpace),
                to: $triggerFrame
            )
        // When the title is capped (e.g. long source names), allow horizontal
        // shrinking so the tail-truncation can take effect; otherwise hug content.
            .fixedSize(
                horizontal: width == nil && maxTitleWidth == nil,
                vertical: true
            )
    }

    private var resolvedMinWidth: CGFloat? {
        width ?? (triggerWidth > 0 ? triggerWidth : nil)
    }

    private var triggerButton: some View {
        Button(action: toggle) {
            DropdownTriggerContent(
                title: title,
                icon: icon,
                width: width,
                maxTitleWidth: maxTitleWidth
            )
        }
        .buttonStyle(SurfaceButtonStyle(kind: .outlined))
        .captureWidth($triggerWidth)
    }

    private var triggerSubButton: some View {
        Button(action: toggle) {
            DropdownTriggerContent(
                title: title,
                icon: icon,
                width: width,
                maxTitleWidth: maxTitleWidth,
                fillWidth: true
            )
        }
        .buttonStyle(SurfaceButtonStyle(kind: .subButton))
    }

    @ViewBuilder
    private var popupContent: some View {
        VStack(
            alignment: .leading,
            spacing: DesktopShellTokens.componentGapXS
        ) {
            content(close)
        }
        .buttonStyle(SurfaceButtonStyle(kind: .subButton))
    }

    private func toggle() {
        guard let dropdownCoordinator else {
            return
        }

        dropdownCoordinator.toggle(
            sourceID: dropdownID,
            frame: triggerFrame,
            style: .outlined,
            minWidth: resolvedMinWidth
        ) {
            triggerSubButton
        } scrollableContent: {
            popupContent
        }
    }

    private func close() {
        dropdownCoordinator?.dismiss()
    }
}

struct DraggableValueField: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String
    let editText: (Double) -> String
    let parse: (String) -> Double?
    var showStepIcon = true
    var fillWidth = false
    var isDisabled = false
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var dragStartValue: Double?
    @FocusState private var isFocused: Bool

    private static let pointsPerStep: CGFloat = 4

    var body: some View {
        buttonSurface(kind: .outlined, isDisabled: isDisabled) {
            HStack(spacing: DesktopShellTokens.componentGapXS) {
                if isEditing {
                    TextField("", text: $draftText)
                        .textFieldStyle(.plain)
                        .font(DesktopShellTypography.labelMD)
                        .foregroundStyle(DesktopShellTokens.actionPrimary)
                        .multilineTextAlignment(fillWidth ? .center : .leading)
                        .focused($isFocused)
                        .onSubmit { commitDraft() }
                        .frame(maxWidth: fillWidth ? .infinity : nil)
                } else {
                    Text(display(value))
                        .font(DesktopShellTypography.labelMD)
                        .foregroundStyle(DesktopShellTokens.actionPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: fillWidth ? .center : .leading)

                    if showStepIcon {
                        KairosIconView(icon: .doubleArrow, color: DesktopShellTokens.actionPrimary)
                            .frame(width: DesktopShellTokens.iconSize, height: DesktopShellTokens.iconSize)
                    }
                }
            }
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: fillWidth ? .center : .leading)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !isDisabled else { return }
                draftText = editText(value)
                isEditing = true
                isFocused = true
            }
        )
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { gesture in
                    guard !isEditing, !isDisabled else { return }
                    if dragStartValue == nil { dragStartValue = value }
                    let steps = (-gesture.translation.height / Self.pointsPerStep).rounded()
                    onCommit(clamped((dragStartValue ?? value) + Double(steps) * step))
                }
                .onEnded { _ in dragStartValue = nil }
        )
        .onChange(of: isFocused) { _, hasFocus in
            if isEditing, !hasFocus { commitDraft() }
        }
    }

    private func commitDraft() {
        defer {
            isEditing = false
            isFocused = false
        }
        let normalized = draftText.replacingOccurrences(of: ",", with: ".")
        if let parsed = parse(normalized) {
            onCommit(clamped(parsed))
        }
    }

    private func clamped(_ next: Double) -> Double {
        min(max(next, range.lowerBound), range.upperBound)
    }
}

struct HoldRepeatButton: View {
    let icon: KairosIcon
    let onStep: () -> Void

    @State private var isHovering = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        buttonSurface(kind: .outlined, isHovered: isHovering) {
            KairosIconView(icon: icon, color: DesktopShellTokens.actionPrimary)
                .frame(width: DesktopShellTokens.iconSize, height: DesktopShellTokens.iconSize)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if holdTask == nil { beginHold() }
                }
                .onEnded { _ in endHold() }
        )
    }

    // Single tap fires once; press-and-hold repeats unit-by-unit with a
    // progressive acceleration while held.
    private func beginHold() {
        onStep()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            var interval: UInt64 = 110_000_000
            while !Task.isCancelled {
                onStep()
                try? await Task.sleep(nanoseconds: interval)
                interval = max(18_000_000, UInt64(Double(interval) * 0.82))
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
    }
}

struct LatencyControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    let editFormatter: (Double) -> String
    let parse: (String) -> Double?
    let onCommit: (Double) -> Void
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        // Figma sidebar: a line of buttons aligned to the right of the row —
        // [−] [value] [+] — matching the other sidebar value controls.
        HStack(spacing: DesktopShellTokens.layoutGapSM) {
            HoldRepeatButton(icon: .minus, onStep: onDecrement)

            DraggableValueField(
                value: value,
                range: range,
                step: step,
                display: formatter,
                editText: editFormatter,
                parse: parse,
                showStepIcon: false,
                onCommit: onCommit
            )

            HoldRepeatButton(icon: .plus, onStep: onIncrement)
        }
    }
}

struct DropdownTriggerContent: View {
    let title: String
    var icon: KairosIcon?
    var width: CGFloat?
    var maxTitleWidth: CGFloat?
    var fillWidth = false

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            Text(title)
                .font(DesktopShellTypography.labelMD)
                .foregroundStyle(DesktopShellTokens.actionPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: maxTitleWidth ?? (fillWidth ? .infinity : nil),
                    alignment: .leading
                )

            if let icon {
                KairosIconView(
                    icon: icon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
        // Fixed width when specified (e.g. preset selector = 146 per Figma) so
        // the trigger never stretches to fill the toolbar; otherwise hug content.
        .frame(width: width, alignment: .leading)
    }
}
