import AppKit
import SwiftUI

struct MenuContentView: View {

    let manager: AudioManager
    let loginItem: LoginItem
    let editor: MultiOutputEditor

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { manager.volume },
            set: { manager.apply(volume: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            volumeSection
            Divider()
            if !manager.members.isEmpty {
                balanceSection
                Divider()
            }
            deviceSection
            Divider()
            multiOutputSection
            Divider()
            // Only shown while the volume keys need a permission. Once they
            // work there is nothing to say.
            if !manager.mediaKeysActive {
                mediaKeysSection
                Divider()
            }
            Toggle("Open at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowFitter())
        .onAppear {
            manager.refreshDevices()
            loginItem.refresh()
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(manager.currentDevice?.name ?? "No Output Device")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int((manager.volume * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(manager.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    manager.toggleMute()
                } label: {
                    Image(systemName: manager.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .disabled(!manager.canControlVolume)
                .help(manager.isMuted ? "Unmute" : "Mute")

                Slider(value: volumeBinding, in: 0...1)
                    .disabled(!manager.canControlVolume)

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            HStack(spacing: 6) {
                stepButton(label: "−10%", delta: -0.10)
                stepButton(label: "−5%", delta: -0.05)
                stepButton(label: "+5%", delta: 0.05)
                stepButton(label: "+10%", delta: 0.10)
            }
            .disabled(!manager.canControlVolume)
        }
    }

    private func stepButton(label: String, delta: Double) -> some View {
        Button(label) { manager.adjustVolume(by: delta) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption.monospacedDigit())
    }

    // MARK: - Balance

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device Balance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(manager.members) { member in
                HStack(spacing: 8) {
                    Text(member.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 100, alignment: .leading)

                    Slider(value: Binding(
                        get: { member.share },
                        set: { manager.setShare($0, for: member) }
                    ), in: 0...1)
                    .controlSize(.small)

                    Text("\(Int((member.share * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Devices

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output Device")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if manager.devices.isEmpty {
                Text("No output devices found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(manager.devices) { device in
                Button {
                    manager.select(device)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .opacity(device.id == manager.currentDevice?.id ? 1 : 0)
                            .frame(width: 12)

                        Text(device.name)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if device.isAggregate {
                            Text("AGG")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        }
                        if !device.canControlVolume {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("No settable volume control")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Multi-output

    /// Devices that can go into a multi-output device.
    private var candidates: [AudioDevice] {
        manager.devices.filter { !$0.isAggregate }
    }

    @ViewBuilder
    private var multiOutputSection: some View {
        if editor.isOpen {
            multiOutputEditor
        } else {
            HStack(spacing: 6) {
                Button("New Multi-Output…") { editor.startCreating() }
                if let device = manager.currentDevice, device.isAggregate {
                    Button("Edit Devices…") { editor.startEditing(device) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
        }
    }

    private var multiOutputEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(editingDevice == nil ? "New Multi-Output Device" : "Edit Multi-Output Device")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Name", text: Binding(get: { editor.name }, set: { editor.name = $0 }))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            ForEach(candidates) { device in
                Toggle(isOn: Binding(
                    get: { editor.isSelected(device) },
                    set: { _ in editor.toggle(device) }
                )) {
                    HStack(spacing: 4) {
                        Text(device.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if editor.selection.first == device.uid {
                            Text("CLOCK")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                                .help("Timing follows this device. The others are drift-corrected to it.")
                        }
                    }
                    .font(.caption)
                }
                .toggleStyle(.checkbox)
            }

            if editor.selection.count < 2 {
                Text("Tick at least two devices.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let message = editor.errorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let device = editingDevice {
                    Button(editor.confirmingDelete ? "Confirm Delete" : "Delete") {
                        if editor.confirmingDelete {
                            editor.delete(device, using: manager)
                        } else {
                            editor.confirmingDelete = true
                        }
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { editor.close() }
                Button(editingDevice == nil ? "Create" : "Save") { editor.save(using: manager) }
                    .disabled(!editor.canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
        }
    }

    private var editingDevice: AudioDevice? {
        if case let .editing(device) = editor.mode { return device }
        return nil
    }

    // MARK: - Media keys

    private var mediaKeysSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(manager.mediaKeyFailure?.summary ?? "Media keys unavailable")
                    .font(.caption)
            }

            // Both permissions shown explicitly — they are separate grants,
            // and a green Accessibility toggle tells you nothing about the
            // other one.
            permissionRow("Accessibility", granted: manager.accessibilityGranted)
            permissionRow("Input Monitoring", granted: manager.inputMonitoringGranted)

            if let failure = manager.mediaKeyFailure {
                Text(failure.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Button("Open Settings…") { manager.requestMediaKeyPermissions() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Retry") { manager.startMediaKeys() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.caption)
        }
    }

    private func permissionRow(_ label: String, granted: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(granted ? Color.green : Color.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Refresh") { manager.refreshDevices() }
                .buttonStyle(.borderless)
                .font(.caption)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Window sizing

/// Keeps the menu bar window the same height as its content, and stops it
/// opening with the first button focused.
///
/// `MenuBarExtra` grows its window when the content grows but does not shrink
/// it again, so once the permission warning disappears an empty strip of
/// window is left behind. This resizes the window to fit, keeping its top edge
/// pinned under the menu bar.
private struct WindowFitter: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView { FittingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FittingView: NSView {
        private var keyObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fit()

            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            guard let window else { return }

            // AppKit focuses the first button (the mute icon) each time the
            // panel opens, which draws a focus ring around it. Clear it once
            // AppKit is done; Tab still moves focus for keyboard users.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                DispatchQueue.main.async { window?.makeFirstResponder(nil) }
            }
        }

        override func layout() {
            super.layout()
            fit()
        }

        private func fit() {
            // This view is the content's background, so its height is the
            // content's height.
            guard let window else { return }
            let height = bounds.height
            guard height > 0, abs(window.contentLayoutRect.height - height) > 0.5 else { return }

            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(
                width: window.contentLayoutRect.width,
                height: height
            )))
            frame.origin.x = window.frame.minX
            frame.origin.y = window.frame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
    }
}
