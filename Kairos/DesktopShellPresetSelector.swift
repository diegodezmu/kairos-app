import SwiftUI

struct PresetSelectorButton: View {
    let activePreset: StoredPreset
    let presets: [StoredPreset]
    let onSelect: (String) -> Void
    let onSave: () -> Void
    let onAdd: () -> Void
    let onRename: (String, String) -> Void
    let onRemove: (String) -> Void

    @Environment(\.floatingDropdownCoordinator) private var dropdownCoordinator
    @State private var dropdownID = UUID()
    @State private var triggerFrame: CGRect = .zero
    @State private var triggerWidth: CGFloat = 0

    var body: some View {
        triggerButton
            .fixedSize(horizontal: true, vertical: true)
            .captureWidth($triggerWidth)
            .captureFrame(
                in: .named(DesktopShellTokens.shellCoordinateSpace),
                to: $triggerFrame
            )
    }

    private var triggerButton: some View {
        Button(action: toggle) {
            DropdownTriggerContent(
                title: activePreset.name,
                icon: .chevronDown,
                maxTitleWidth: DesktopShellTokens.ghostButtonTriggerTitleMaxWidth
            )
        }
        .help(activePreset.name)
        .buttonStyle(SurfaceButtonStyle(kind: .ghost))
    }

    @ViewBuilder
    private var popupHeader: some View {
        PresetMenuItem(
            title: activePreset.name,
            showsDisclosure: true,
            maxTitleWidth: DesktopShellTokens.ghostButtonFoldedHeaderTitleMaxWidth,
            action: toggle,
            onRename: activePreset.isDefault ? nil : { nextName in
                onRename(activePreset.id, nextName)
            },
            onRemove: activePreset.isDefault ? nil : {
                onRemove(activePreset.id)
                close()
            }
        )
    }

    @ViewBuilder
    private var popupBody: some View {
        VStack(
            alignment: .leading,
            spacing: DesktopShellTokens.componentGapLG
        ) {
            VStack(
                alignment: .leading,
                spacing: DesktopShellTokens.componentGapXS
            ) {
                ForEach(presets, id: \.id) { preset in
                    PresetMenuItem(
                        title: preset.name,
                        maxTitleWidth: DesktopShellTokens.ghostButtonFoldedItemTitleMaxWidth,
                        fillWidth: true,
                        action: {
                            onSelect(preset.id)
                            close()
                        },
                        onRename: preset.isDefault ? nil : { nextName in
                            onRename(preset.id, nextName)
                        },
                        onRemove: preset.isDefault ? nil : {
                            onRemove(preset.id)
                            close()
                        }
                    )
                }
            }

            VStack(
                alignment: .leading,
                spacing: DesktopShellTokens.componentGapXS
            ) {
                Button {
                    onSave()
                    close()
                } label: {
                    Text("save")
                        .font(DesktopShellTypography.labelMD)
                        .foregroundStyle(
                            DesktopShellTokens.actionPrimary
                        )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    SurfaceButtonStyle(kind: .modalSecondary)
                )

                Button {
                    onAdd()
                    close()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        KairosIconView(
                            icon: .plus,
                            color: DesktopShellTokens.actionPrimary
                        )
                        .frame(
                            width: DesktopShellTokens.iconSize,
                            height: DesktopShellTokens.iconSize
                        )
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(
                    SurfaceButtonStyle(kind: .modalSecondary)
                )
            }
        }
    }

    private func toggle() {
        guard let dropdownCoordinator else {
            return
        }

        dropdownCoordinator.toggle(
            sourceID: dropdownID,
            frame: triggerFrame,
            style: .ghost,
            minWidth: resolvedMinWidth
        ) {
            popupHeader
        } scrollableContent: {
            popupBody
        }
    }

    private func close() {
        dropdownCoordinator?.dismiss()
    }

    private var resolvedMinWidth: CGFloat? {
        guard triggerWidth > 0 else {
            return nil
        }

        return min(triggerWidth, DesktopShellTokens.ghostButtonMaxWidth)
    }
}

struct PresetMenuItem: View {
    let title: String
    var showsDisclosure = false
    var maxTitleWidth: CGFloat? = nil
    var fillWidth = false
    let action: () -> Void
    var onRename: ((String) -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @State private var isRenamePresented = false
    @State private var draftName = ""

    private var supportsContextMenu: Bool {
        onRename != nil || onRemove != nil
    }

    var body: some View {
        if supportsContextMenu {
            button
                .contextMenu {
                    if onRename != nil {
                        Button("Rename") {
                            draftName = title
                            isRenamePresented = true
                        }
                    }

                    if let onRemove {
                        Button("Remove", role: .destructive) {
                            onRemove()
                        }
                    }
                }
                .popover(isPresented: $isRenamePresented) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rename preset")
                            .font(DesktopShellTypography.titleSM)

                        TextField("Preset name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)

                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isRenamePresented = false
                            }
                            Button("Apply") {
                                let trimmedName = draftName
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                if !trimmedName.isEmpty {
                                    onRename?(trimmedName)
                                }
                                isRenamePresented = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(16)
                }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            DropdownTriggerContent(
                title: title,
                icon: showsDisclosure ? .chevronDown : nil,
                maxTitleWidth: maxTitleWidth,
                fillWidth: fillWidth
            )
        }
        .help(title)
        .buttonStyle(SurfaceButtonStyle(kind: .subButton))
    }
}
