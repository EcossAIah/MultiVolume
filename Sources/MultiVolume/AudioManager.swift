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

    /// One device inside a multi-output device. Its volume is the main volume
    /// times its share, so the volume keys keep the balance between them.
    struct Member: Identifiable, Hashable {
        let id: AudioObjectID
        let uid: String
        let name: String
        var share: Double
    }

    private(set) var devices: [AudioDevice] = []
    private(set) var currentDevice: AudioDevice?
    private(set) var volume: Double = 0
    private(set) var isMuted: Bool = false
    /// Empty unless the current device is a multi-output device with more than
    /// one sub-device to balance.
    private(set) var members: [Member] = []

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
    @ObservationIgnored private let hud = VolumeHUD()
    @ObservationIgnored private let feedback = VolumeFeedback()

    init() {
        hud.onSetVolume = { [weak self] in self?.apply(volume: $0); self?.updateHUD() }
        hud.onMute = { [weak self] in self?.setMuted(true); self?.updateHUD() }
        hud.onMaximize = { [weak self] in
            self?.apply(volume: 1)
            self?.updateHUD()
            self?.feedback.play()
        }
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
        loadMembers()
        installDeviceListeners()
        refreshLevels()
    }

    func refreshLevels() {
        guard let device = currentDevice else {
            volume = 0
            isMuted = false
            return
        }
        let level = readLevel(of: device)
        volume = level
        isMuted = VolumeControl.isMuted(device) || (softwareMuted && level <= 0.0001)
    }

    // MARK: - Actions

    func apply(volume newValue: Double) {
        guard let device = currentDevice, device.canControlVolume else { return }
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        writeLevel(clamped, to: device)

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
                writeLevel(0, to: device)
            } else {
                writeLevel(volumeBeforeMute ?? 0.25, to: device)
            }
        } else {
            softwareMuted = false
        }

        isMuted = muted
        refreshLevels()
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Sets how loud one sub-device is relative to the others, and remembers it.
    func setShare(_ share: Double, for member: Member) {
        guard let device = currentDevice,
              let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].share = min(max(share, 0), 1)

        var saved = savedShares(for: device)
        saved[member.uid] = members[index].share
        UserDefaults.standard.set(saved, forKey: sharesKey(for: device))

        if !softwareMuted {
            VolumeControl.setVolume(Float(volume * members[index].share), onTarget: member.id)
        }
    }

    // MARK: - Balance

    private func loadMembers() {
        guard let device = currentDevice, device.isAggregate, device.volumeTargets.count > 1 else {
            members = []
            return
        }
        let saved = savedShares(for: device)
        members = device.volumeTargets.map { target in
            let uid = AudioCatalog.uid(of: target)
            return Member(id: target, uid: uid, name: AudioCatalog.name(of: target), share: saved[uid] ?? 1)
        }
    }

    private func sharesKey(for device: AudioDevice) -> String { "shares.\(device.uid)" }

    private func savedShares(for device: AudioDevice) -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: sharesKey(for: device)) as? [String: Double] ?? [:]
    }

    private func writeLevel(_ level: Double, to device: AudioDevice) {
        guard !members.isEmpty else {
            VolumeControl.setVolume(Float(level), on: device)
            return
        }
        for member in members {
            VolumeControl.setVolume(Float(level * member.share), onTarget: member.id)
        }
    }

    /// The main volume is whatever, times each share, gives the sub-device
    /// volumes; the loudest-relative sub-device decides it.
    private func readLevel(of device: AudioDevice) -> Double {
        let scaled = members.compactMap { member -> Double? in
            guard member.share > 0.01, let level = VolumeControl.volume(ofTarget: member.id) else { return nil }
            return Double(level) / member.share
        }
        guard let level = scaled.max() else {
            return members.isEmpty ? Double(VolumeControl.volume(of: device) ?? 0) : volume
        }
        return min(level, 1)
    }

    private func updateHUD() {
        hud.update(level: volume, isMuted: isMuted)
    }

    func select(_ device: AudioDevice) {
        try? AudioCatalog.setDefaultOutputDevice(device.id)
        refreshDevices()
    }

    // MARK: - Multi-output devices

    /// Creates the device and switches output to it.
    func createMultiOutput(name: String, subDeviceUIDs: [String]) throws {
        let id = try MultiOutputDevices.create(name: name, subDeviceUIDs: subDeviceUIDs)
        try? AudioCatalog.setDefaultOutputDevice(id)
        refreshDevices()
    }

    func updateMultiOutput(_ device: AudioDevice, name: String, subDeviceUIDs: [String]) throws {
        let wasDefault = device.id == currentDevice?.id
        let id = try MultiOutputDevices.rebuild(device, name: name, subDeviceUIDs: subDeviceUIDs)
        if wasDefault { try? AudioCatalog.setDefaultOutputDevice(id) }
        refreshDevices()
    }

    func deleteMultiOutput(_ device: AudioDevice) throws {
        try MultiOutputDevices.destroy(device.id)
        UserDefaults.standard.removeObject(forKey: sharesKey(for: device))
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

        let step = 1.0 / 16.0

        switch key {
        case .volumeUp:
            adjustVolume(by: step)
            feedback.play()
        case .volumeDown:
            adjustVolume(by: -step)
            feedback.play()
        case .mute:
            if !isRepeat { toggleMute() }
        }
        hud.show(level: volume, isMuted: isMuted, deviceName: device.name)
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
