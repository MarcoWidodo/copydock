import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        settings: AppSettings,
        onResetLayout: @escaping () -> Void,
        onHardReset: @escaping () -> Void
    ) {
        let rootView = SettingsView(
            settings: settings,
            onResetLayout: onResetLayout,
            onHardReset: onHardReset
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "CopyDock Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 690))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onResetLayout: () -> Void
    let onHardReset: () -> Void
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Background", selection: $settings.backgroundStyle) {
                    ForEach(DockBackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Slot style", selection: $settings.slotShape) {
                    ForEach(SlotShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)

                Picker(
                    "Color palette",
                    selection: Binding(
                        get: { settings.selectedPalette },
                        set: { settings.applyPalette($0) }
                    )
                ) {
                    ForEach(ColorPalettePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                ColorPicker(
                    "Accent color",
                    selection: Binding(
                        get: { Color(nsColor: settings.accentColor) },
                        set: { settings.accentHex = NSColor($0).hexString }
                    ),
                    supportsOpacity: false
                )

                ColorPicker(
                    "Unaccented slot color",
                    selection: Binding(
                        get: { Color(nsColor: settings.slotBaseColor) },
                        set: { settings.slotBaseHex = NSColor($0).hexString }
                    ),
                    supportsOpacity: false
                )

                ColorPicker(
                    "Glass or solid background color",
                    selection: Binding(
                        get: { Color(nsColor: settings.dockBackgroundColor) },
                        set: { settings.backgroundHex = NSColor($0).hexString }
                    ),
                    supportsOpacity: false
                )

                HStack {
                    Text("Slot size")
                    Slider(value: $settings.slotSize, in: 44...86, step: 1)
                    Text("\(Int(settings.slotSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }

                HStack {
                    Text("Opacity")
                    Slider(value: $settings.opacity, in: 0.35...1, step: 0.01)
                    Text("\(Int(settings.opacity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Section("Placement") {
                Picker("Screen edge", selection: $settings.position) {
                    ForEach(DockPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Snap to the nearest edge after dragging", isOn: $settings.edgeSnapping)
            }

            Section("Behavior") {
                Toggle("Show previews after hovering for one second", isOn: $settings.hoverPreviews)

                HStack {
                    Text("Preview width")
                    Slider(value: $settings.previewWidth, in: 280...720, step: 10)
                    Text("\(Int(settings.previewWidth)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }

                HStack {
                    Text("Preview height")
                    Slider(value: $settings.previewHeight, in: 180...600, step: 10)
                    Text("\(Int(settings.previewHeight)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }

                HStack {
                    Text("Text shown")
                    Slider(value: $settings.previewCharacterLimit, in: 500...10_000, step: 500)
                    Text("\(Int(settings.previewCharacterLimit / 1_000))k chars")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }

                HStack {
                    Text("Maximum item size")
                    Slider(value: $settings.maximumCaptureMegabytes, in: 5...200, step: 5)
                    Text("\(Int(settings.maximumCaptureMegabytes)) MB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }

                HStack {
                    Button("Reset Dock Layout", action: onResetLayout)
                    Spacer()
                    Button("Hard Reset CopyDock…") { showResetConfirmation = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 520, minHeight: 670)
        .alert("Hard reset CopyDock?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: onHardReset)
        } message: {
            Text("This clears all nine slots and restores every appearance and placement setting to its default.")
        }
    }
}
