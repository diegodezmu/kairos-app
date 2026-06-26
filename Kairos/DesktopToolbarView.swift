import SwiftUI

struct DesktopToolbarView: View {
    let model: DesktopShellModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.toolbarSnapshot(at: timeline.date)

            HStack(spacing: DesktopShellTokens.componentGapXL) {
                HStack(spacing: DesktopShellTokens.componentGapXL) {
                    Text("KAIROS")
                        .font(DesktopShellTypography.wordmark)
                        .foregroundStyle(DesktopShellTokens.textTertiary)

                    PresetSelectorButton(
                        activePreset: model.activePreset,
                        presets: model.availablePresets,
                        onSelect: { presetID in
                            model.selectPreset(presetID)
                        },
                        onSave: {
                            Task {
                                await model.saveCurrentPreset()
                            }
                        },
                        onAdd: {
                            Task {
                                await model.addPreset()
                            }
                        },
                        onRename: { presetID, name in
                            Task {
                                await model.renamePreset(presetID, to: name)
                            }
                        },
                        onRemove: { presetID in
                            Task {
                                await model.removePreset(presetID)
                            }
                        }
                    )

                    HStack(spacing: DesktopShellTokens.componentGapXS) {
                        ToolbarIconButton(
                            icon: model.isSidebarVisible ? .sidebar : .sidebarFolded,
                            isActive: model.isSidebarVisible,
                            action: model.toggleSidebar
                        )

                        ToolbarIconButton(
                            icon: model.isPreviewPlaying ? .stop : .play,
                            isDisabled: !model.canControlTransport,
                            action: model.togglePlay
                        )

                        ToolbarIconButton(
                            icon: .reset,
                            action: model.resetPreview
                        )

                        ToolbarIconButton(
                            icon: model.metronomeToolbarIcon(at: timeline.date),
                            isActive: model.settings.isMetronomeEnabled,
                            action: model.toggleMetronome
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DesktopToolbarLiveDataView(
                    snapshot: snapshot,
                    canEditTempo: model.canEditTempo
                )
                .fixedSize()
            }
            .padding(.horizontal, DesktopShellTokens.componentGapLG)
            .padding(.vertical, DesktopShellTokens.componentGapSM)
            .frame(height: DesktopShellTokens.toolbarHeight)
            .background(DesktopShellTokens.backgroundCanvas)
        }
    }
}

struct DesktopToolbarLiveDataView: View {
    let snapshot: DesktopToolbarSnapshot
    let canEditTempo: Bool

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapLG) {
            DataAtomView(
                text: snapshot.elapsedText,
                width: DesktopShellTokens.toolbarTimeWidth
            )
            DataAtomView(
                text: snapshot.bpmText,
                width: DesktopShellTokens.toolbarBPMWidth,
                isDisabled: !canEditTempo
            )
            // Sync status hugs its content and the whole cluster is pinned to the
            // trailing edge, so the data is flush with the layout's right margin
            // (no empty gap after the sync text), per the Figma toolbar.
            SyncStatusView(descriptor: snapshot.syncStatus)
                .layoutPriority(1)
        }
    }
}
