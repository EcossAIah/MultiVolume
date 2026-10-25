import AppKit
import SwiftUI

struct MenuContentView: View {

    let manager: AudioManager

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
            deviceSection
            Divider()
            mediaKeysSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { manager.refreshDevices() }
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

    // MARK: - Media keys

    @ViewBuilder
    private var mediaKeysSection: some View {
        if manager.mediaKeysActive {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Media keys active")
                        .font(.caption)
                    Text("Used only for aggregate devices; ⇧⌥ for fine steps")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
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
