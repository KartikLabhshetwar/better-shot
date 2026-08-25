//
//  RecordingStudioStylePresetBar.swift
//  BetterShot
//

import AppKit
import SwiftUI

struct RecordingStudioStylePresetBar: View {
    @Bindable var model: RecordingStudioModel
    @Bindable var presetStore: RecordingStudioStylePresetStore

    @State private var isNameEditorPresented = false
    @State private var draftName = ""
    @State private var presetPendingDeletion: RecordingStudioStylePreset?
    @FocusState private var isNameFieldFocused: Bool

    private var appliedPreset: RecordingStudioStylePreset? {
        presetStore.preset(id: model.appliedStylePresetID)
    }

    private var duplicateNamePreset: RecordingStudioStylePreset? {
        presetStore.preset(named: draftName)
    }

    private var displayTitle: String {
        appliedPreset?.name ?? "Presets…"
    }

    private var isAppliedPresetModified: Bool {
        guard let appliedPreset else { return false }
        return !appliedPreset.matches(model.style)
    }

    private var canSaveName: Bool {
        !RecordingStudioStylePresetStore.normalizedName(draftName).isEmpty
            && duplicateNamePreset == nil
            && !model.style.hasMissingCustomWallpaper
    }

    var body: some View {
        HStack(spacing: 7) {
            presetMenu
                .layoutPriority(1)

            if let appliedPreset {
                PresetBarIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "Delete \(appliedPreset.name)",
                    help: "Delete \(appliedPreset.name)"
                ) {
                    presetPendingDeletion = appliedPreset
                }
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }

            PresetBarIconButton(
                systemImage: "plus",
                accessibilityLabel: "Add Preset",
                help: "Save current settings as a preset"
            ) {
                draftName = ""
                isNameEditorPresented = true
            }
            .popover(isPresented: $isNameEditorPresented, arrowEdge: .top) {
                nameEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
        .padding(.vertical, 9)
        .animation(.snappy(duration: 0.18), value: appliedPreset?.id)
        .alert(
            "Delete Preset?",
            isPresented: Binding(
                get: { presetPendingDeletion != nil },
                set: { if !$0 { presetPendingDeletion = nil } }
            ),
            presenting: presetPendingDeletion
        ) { preset in
            Button("Delete", role: .destructive) {
                presetStore.deletePreset(id: preset.id)
                if model.appliedStylePresetID == preset.id {
                    model.appliedStylePresetID = nil
                }
                presetPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                presetPendingDeletion = nil
            }
        } message: { preset in
            Text("“\(preset.name)” will be removed from your saved presets. The current recording won’t change.")
        }
    }

    private var presetMenu: some View {
        RecordingStudioStylePresetPopUpButton(
            title: displayTitle,
            presets: presetStore.presets,
            appliedPresetID: isAppliedPresetModified ? nil : model.appliedStylePresetID,
            defaultPresetID: presetStore.activePreset?.id,
            accessibilityValue: presetAccessibilityValue,
            onSelectPreset: selectPreset,
            onSetDefaultPreset: { presetStore.setActivePreset(id: $0) },
            onDeletePreset: { presetID in
                guard let preset = presetStore.preset(id: presetID) else { return }
                presetPendingDeletion = preset
            }
        )
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .help(presetHelp)
    }

    private func selectPreset(_ presetID: RecordingStudioStylePreset.ID?) {
        guard let preset = presetStore.preset(id: presetID) else {
            model.appliedStylePresetID = nil
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            model.applyStylePreset(preset)
        }
    }

    private var presetHelp: String {
        if let activePreset = presetStore.activePreset {
            return "Choose a preset. \(activePreset.name) is applied to new recordings."
        }
        return "Choose a background, layout, cursor, and camera preset"
    }

    private var presetAccessibilityValue: String {
        var details = [displayTitle]
        if isAppliedPresetModified {
            details.append("modified")
        }
        if appliedPreset?.hasMissingWallpaper == true {
            details.append("wallpaper missing")
        }
        return details.joined(separator: ", ")
    }

    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Preset")
                    .font(.system(size: 14, weight: .semibold))

                Text("Save the current background, layout, cursor size, and camera settings. It will be used for new recordings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Preset name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .onSubmit(savePreset)
                    .onChange(of: draftName) { _, newValue in
                        let limitedName = String(
                            newValue.prefix(RecordingStudioStylePresetStore.maximumNameLength)
                        )
                        if limitedName != newValue {
                            draftName = limitedName
                        }
                    }

                if model.style.hasMissingCustomWallpaper {
                    Label(
                        "The selected wallpaper can’t be found. Choose it again before saving.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                } else if duplicateNamePreset != nil {
                    Label(
                        "A preset with this name already exists.",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    isNameEditorPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    savePreset()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveName)
            }
        }
        .padding(16)
        .frame(width: 292)
        .onAppear {
            Task { @MainActor in
                isNameFieldFocused = true
            }
        }
    }

    private func savePreset() {
        guard canSaveName else { return }
        guard let preset = presetStore.savePreset(named: draftName, style: model.style) else {
            return
        }
        model.appliedStylePresetID = preset.id
        presetStore.setActivePreset(id: preset.id)
        isNameEditorPresented = false
    }
}

private struct RecordingStudioStylePresetPopUpButton: NSViewRepresentable {
    let title: String
    let presets: [RecordingStudioStylePreset]
    let appliedPresetID: RecordingStudioStylePreset.ID?
    let defaultPresetID: RecordingStudioStylePreset.ID?
    let accessibilityValue: String
    let onSelectPreset: (RecordingStudioStylePreset.ID?) -> Void
    let onSetDefaultPreset: (RecordingStudioStylePreset.ID?) -> Void
    let onDeletePreset: (RecordingStudioStylePreset.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.usesItemFromMenu = false
        button.autoenablesItems = false
        button.altersStateOfSelectedItem = false
        button.preferredEdge = .minY
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.alignment = .left
        button.cell?.lineBreakMode = .byTruncatingTail
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(button)
    }

    final class Coordinator: NSObject {
        var parent: RecordingStudioStylePresetPopUpButton

        init(parent: RecordingStudioStylePresetPopUpButton) {
            self.parent = parent
        }

        func update(_ button: NSPopUpButton) {
            button.menu = makeMenu()
            let displayItem = NSMenuItem(
                title: parent.title,
                action: nil,
                keyEquivalent: ""
            )
            (button.cell as? NSPopUpButtonCell)?.menuItem = displayItem
            button.setAccessibilityLabel("Studio style preset")
            button.setAccessibilityValue(parent.accessibilityValue)
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let availablePresets = parent.presets.filter { !$0.hasMissingWallpaper }
            let missingPresets = parent.presets.filter(\.hasMissingWallpaper)

            if availablePresets.isEmpty && missingPresets.isEmpty {
                let emptyItem = NSMenuItem(title: "No Saved Presets", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
                return menu
            }

            if !availablePresets.isEmpty {
                menu.addItem(.sectionHeader(title: "Saved Presets"))

                let currentItem = NSMenuItem(
                    title: "Current Settings",
                    action: #selector(selectCurrentSettings(_:)),
                    keyEquivalent: ""
                )
                currentItem.target = self
                currentItem.state = parent.appliedPresetID == nil ? .on : .off
                menu.addItem(currentItem)

                for preset in availablePresets {
                    let item = presetItem(
                        preset,
                        action: #selector(selectPreset(_:)),
                        isSelected: preset.id == parent.appliedPresetID
                    )
                    menu.addItem(item)
                }
            }

            if !missingPresets.isEmpty {
                if !availablePresets.isEmpty {
                    menu.addItem(.separator())
                }
                menu.addItem(.sectionHeader(title: "Wallpaper Missing"))

                for preset in missingPresets {
                    let item = presetItem(
                        preset,
                        action: #selector(deletePreset(_:)),
                        isSelected: false
                    )
                    item.title = "Delete “\(preset.name)”…"
                    item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                    menu.addItem(item)
                }
            }

            if !availablePresets.isEmpty {
                menu.addItem(.separator())

                let defaultItem = NSMenuItem(title: "Default Preset", action: nil, keyEquivalent: "")
                defaultItem.submenu = makeDefaultMenu(presets: availablePresets)
                menu.addItem(defaultItem)
            }

            return menu
        }

        private func makeDefaultMenu(presets: [RecordingStudioStylePreset]) -> NSMenu {
            let menu = NSMenu(title: "Default Preset")
            menu.autoenablesItems = false

            let noneItem = NSMenuItem(
                title: "None",
                action: #selector(clearDefaultPreset(_:)),
                keyEquivalent: ""
            )
            noneItem.target = self
            noneItem.state = parent.defaultPresetID == nil ? .on : .off
            menu.addItem(noneItem)

            for preset in presets {
                let item = presetItem(
                    preset,
                    action: #selector(setDefaultPreset(_:)),
                    isSelected: preset.id == parent.defaultPresetID
                )
                menu.addItem(item)
            }

            return menu
        }

        private func presetItem(
            _ preset: RecordingStudioStylePreset,
            action: Selector,
            isSelected: Bool
        ) -> NSMenuItem {
            let item = NSMenuItem(title: preset.name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id.uuidString
            item.state = isSelected ? .on : .off
            return item
        }

        private func presetID(from sender: NSMenuItem) -> RecordingStudioStylePreset.ID? {
            guard let rawValue = sender.representedObject as? String else { return nil }
            return UUID(uuidString: rawValue)
        }

        @objc private func selectCurrentSettings(_ sender: NSMenuItem) {
            parent.onSelectPreset(nil)
        }

        @objc private func selectPreset(_ sender: NSMenuItem) {
            guard let presetID = presetID(from: sender) else { return }
            parent.onSelectPreset(presetID)
        }

        @objc private func clearDefaultPreset(_ sender: NSMenuItem) {
            parent.onSetDefaultPreset(nil)
        }

        @objc private func setDefaultPreset(_ sender: NSMenuItem) {
            guard let presetID = presetID(from: sender) else { return }
            parent.onSetDefaultPreset(presetID)
        }

        @objc private func deletePreset(_ sender: NSMenuItem) {
            guard let presetID = presetID(from: sender) else { return }
            parent.onDeletePreset(presetID)
        }
    }
}

private struct PresetBarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovering = $0 }
    }
}
