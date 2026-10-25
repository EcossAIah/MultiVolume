import AppKit
import CoreAudio
import Observation
import SwiftUI

/// Single source of truth for the menu bar UI.
///
/// Follows the system default output device: changing the selection in the menu
/// changes the system default, exactly like the Sound menu, and volume always
/// applies to whatever is currently default.
@MainActor
@Observable
final class AudioManager {

    private(set) var devices: [AudioDevice] = []
    private(set) var currentDevice: AudioDevice?
    private(set) var volume: Double = 0
    private(set) var isMuted: Bool = false

    private(set) var accessibilityGranted = MediaKeyMonitor.hasAccessibilityPermission
    private(set) var inputMonitoringGranted = MediaKeyMonitor.hasInputMonitoringPermission
    private(set) var mediaKeysActive = false
    private(set) var mediaKeyFailure: MediaKeyFailure?

    @ObservationIgnored private var systemListeners: [PropertyListener] = []
    @ObservationIgnored private var deviceListeners: [PropertyListener] = []
    @ObservationIgnored private var softwareMuted = false
    @ObservationIgnored private var volumeBeforeMute: Double?
    @ObservationIgnored private var mediaKeys: MediaKeyMonitor?
    @ObservationIgnored private var permissionTimer: Timer?

    init() {
        refreshDevices()
        installSystemListeners()
        startMediaKeys()
    }

    // MARK: - Derived state

    var canControlVolume: Bool { currentDevice?.canControlVolume ?? false }

    var statusDescription: String {
        guard let device = currentDevice else { return "No output device" }
        if !device.canControlVolume {
            return device.isAggregate
                ? "No sub-device exposes a volume control"
                : "This device has no software volume control"
        }
        return device.isAggregate
            ? "Aggregate — driving \(device.volumeTargets.count) sub-device\(device.volumeTargets.count == 1 ? "" : "s")"
            : "Hardware volume"
    }

    var iconName: String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: - Refresh

    func refreshDevices() {
        devices = AudioCatalog.outputDevices()
        let defaultID = AudioCatalog.defaultOutputDeviceID()
        currentDevice = devices.first { $0.id == defaultID }
        installDeviceListeners()
        refreshLevels()
    }

    func refreshLevels() {
        guard let device = currentDevice else {
            volume = 0
            isMuted = false
            return
        }
        let level = Double(VolumeControl.volume(of: device) ?? 0)
        volume = level
        isMuted = VolumeControl.isMuted(device) || (softwareMuted && level <= 0.0001)
    }

    // MARK: - Actions

    func apply(volume newValue: Double) {
        guard let device = currentDevice, device.canControlVolume else { return }
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        VolumeControl.setVolume(Float(clamped), on: device)

        if clamped > 0.0001 {
            softwareMuted = false
            if isMuted { VolumeControl.setMuted(false, on: device) }
            isMuted = false
        }
    }

    func adjustVolume(by delta: Double) {
        apply(volume: volume + delta)
    }

    func setMuted(_ muted: Bool) {
        guard let device = currentDevice, device.canControlVolume else { return }

        // Prefer the hardware mute control; fall back to volume 0 for devices
        // (many aggregates) that expose no mute property.
        let hardwareHandled = VolumeControl.setMuted(muted, on: device)
        if !hardwareHandled {
            softwareMuted = muted
            if muted {
                volumeBeforeMute = volume
                VolumeControl.setVolume(0, on: device)
            } else {
                VolumeControl.setVolume(Float(volumeBeforeMute ?? 0.25), on: device)
            }
        } else {
            softwareMuted = false
        }

        isMuted = muted
        refreshLevels()
    }

    func toggleMute() { setMuted(!isMuted) }

    func select(_ device: AudioDevice) {
        try? AudioCatalog.setDefaultOutputDevice(device.id)
        refreshDevices()
    }

    // MARK: - Media keys

    func startMediaKeys() {
        accessibilityGranted = MediaKeyMonitor.hasAccessibilityPermission
        inputMonitoringGranted = MediaKeyMonitor.hasInputMonitoringPermission

        if mediaKeys == nil {
            mediaKeys = MediaKeyMonitor { [weak self] key, isPressed, isRepeat in
                MainActor.assumeIsolated {
                    self?.handleMediaKey(key, isPressed: isPressed, isRepeat: isRepeat) ?? false
                }
            }
        }

        mediaKeysActive = mediaKeys?.start() ?? false
        mediaKeyFailure = mediaKeysActive ? nil : mediaKeys?.lastFailure

        if mediaKeysActive {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            schedulePermissionCheck()
        }
    }

    /// Asks for whichever permission is actually missing, in order, and opens
    /// the matching Settings pane. Accessibility and Input Monitoring are
    /// separate grants; granting one does not imply the other.
    func requestMediaKeyPermissions() {
        if !MediaKeyMonitor.hasAccessibilityPermission {
            MediaKeyMonitor.requestAccessibilityPermission()
            MediaKeyMonitor.openAccessibilitySettings()
        } else if !MediaKeyMonitor.hasInputMonitoringPermission {
            MediaKeyMonitor.requestInputMonitoringPermission()
            MediaKeyMonitor.openInputMonitoringSettings()
        } else {
            // Both granted but the tap was refused — usually a stale TCC entry
            // after a rebuild changed the code signature.
            MediaKeyMonitor.openAccessibilitySettings()
        }
        startMediaKeys()
    }

    private func schedulePermissionCheck() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.mediaKeysActive else { return }
                self.startMediaKeys()
            }
        }
    }

    /// Returns `true` when this app takes ownership of the key press.
    ///
    /// We only take over for aggregate / multi-output devices, where the
    /// system's own volume handling is a silent no-op. For every ordinary
    /// device the event is passed straight through, so macOS keeps its native
    /// behaviour and its on-screen volume HUD, and this app changes nothing.
    private func handleMediaKey(_ key: MediaKey, isPressed: Bool, isRepeat: Bool) -> Bool {
        guard let device = currentDevice, device.isAggregate, device.canControlVolume else {
            return false
        }

        // Consume the matching key-up too, so the system never sees half an event.
        guard isPressed else { return true }

        let modifiers = NSEvent.modifierFlags
        let fine = modifiers.contains(.shift) && modifiers.contains(.option)
        let step = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch key {
        case .volumeUp:
            adjustVolume(by: step)
        case .volumeDown:
            adjustVolume(by: -step)
        case .mute:
            if !isRepeat { toggleMute() }
        }
        return true
    }

    // MARK: - Listeners

    private func installSystemListeners() {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice
        ]

        systemListeners = selectors.compactMap { selector in
            PropertyListener(
                objectID: HAL.system,
                address: HAL.address(selector),
                handler: { [weak self] in
                    MainActor.assumeIsolated { self?.refreshDevices() }
                }
            )
        }
    }

    private func installDeviceListeners() {
        // Replacing the array deallocates the old listeners, which removes them.
        deviceListeners = []
        guard let device = currentDevice else { return }

        var listeners: [PropertyListener] = []
        for target in device.volumeTargets {
            var addresses: [AudioObjectPropertyAddress] = [
                HAL.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
            ]
            for element in VolumeControl.volumeElements(for: target) {
                addresses.append(
                    HAL.address(
                        kAudioDevicePropertyVolumeScalar,
                        scope: kAudioObjectPropertyScopeOutput,
                        element: element
                    )
                )
            }

            for address in addresses {
                if let listener = PropertyListener(
                    objectID: target,
                    address: address,
                    handler: { [weak self] in
                        MainActor.assumeIsolated { self?.refreshLevels() }
                    }
                ) {
                    listeners.append(listener)
                }
            }
        }
        deviceListeners = listeners
    }
}
