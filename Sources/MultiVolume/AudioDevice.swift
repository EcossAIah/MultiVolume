import CoreAudio
import Foundation

// MARK: - Model

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isAggregate: Bool

    /// The devices whose volume we actually drive.
    ///
    /// For a normal device this is just the device itself. For an aggregate or
    /// multi-output device it is the list of active sub-devices that expose a
    /// settable volume control — which is the entire reason this app exists,
    /// since the aggregate itself exposes no volume property and the system
    /// volume control therefore does nothing.
    let volumeTargets: [AudioObjectID]

    var canControlVolume: Bool { !volumeTargets.isEmpty }
}

// MARK: - Device discovery

enum AudioCatalog {

    static func outputDevices() -> [AudioDevice] {
        let addr = HAL.address(kAudioHardwarePropertyDevices)
        guard let ids = try? HAL.readObjectList(HAL.system, addr) else { return [] }

        return ids.compactMap { makeDevice($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func defaultOutputDeviceID() -> AudioObjectID? {
        let addr = HAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        guard let id = try? HAL.read(HAL.system, addr, as: AudioObjectID.self), id != kAudioObjectUnknown else {
            return nil
        }
        return id
    }

    static func setDefaultOutputDevice(_ id: AudioObjectID) throws {
        let addr = HAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        try HAL.write(HAL.system, addr, id)
    }

    // MARK: Private

    private static func makeDevice(_ id: AudioObjectID) -> AudioDevice? {
        guard hasOutputStreams(id), isUserSelectable(id) else { return nil }

        let name = (try? HAL.readString(id, HAL.address(kAudioObjectPropertyName))) ?? "Unknown Device"
        let uid = (try? HAL.readString(id, HAL.address(kAudioDevicePropertyDeviceUID))) ?? ""
        let aggregate = isAggregate(id)

        let ownVolume = VolumeControl.volumeElements(for: id).isEmpty ? [] : [id]

        let targets: [AudioObjectID]
        if aggregate {
            let subTargets = activeSubDevices(id).filter { !VolumeControl.volumeElements(for: $0).isEmpty }
            // Almost always the sub-devices. Fall back to the aggregate itself
            // in the rare case it exposes a settable volume of its own.
            targets = subTargets.isEmpty ? ownVolume : subTargets
        } else {
            targets = ownVolume
        }

        return AudioDevice(id: id, uid: uid, name: name, isAggregate: aggregate, volumeTargets: targets)
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        let addr = HAL.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        guard let streams = try? HAL.readObjectList(id, addr) else { return false }
        return !streams.isEmpty
    }

    /// Matches the Sound menu: skips devices that mark themselves hidden or
    /// not eligible as the default output, such as Zoom's private
    /// `ZoomAudioDevice`. A device that does not report a value is kept.
    private static func isUserSelectable(_ id: AudioObjectID) -> Bool {
        let hidden = HAL.address(kAudioDevicePropertyIsHidden)
        if let value = try? HAL.read(id, hidden, as: UInt32.self), value != 0 {
            return false
        }
        let canBeDefault = HAL.address(
            kAudioDevicePropertyDeviceCanBeDefaultDevice,
            scope: kAudioObjectPropertyScopeOutput
        )
        if let value = try? HAL.read(id, canBeDefault, as: UInt32.self), value == 0 {
            return false
        }
        return true
    }

    private static func isAggregate(_ id: AudioObjectID) -> Bool {
        let addr = HAL.address(kAudioDevicePropertyTransportType)
        guard let transport = try? HAL.read(id, addr, as: UInt32.self) else { return false }
        // Covers both "Aggregate Device" and "Multi-Output Device" from Audio MIDI Setup.
        return transport == kAudioDeviceTransportTypeAggregate
    }

    private static func activeSubDevices(_ id: AudioObjectID) -> [AudioObjectID] {
        let addr = HAL.address(kAudioAggregateDevicePropertyActiveSubDeviceList)
        return (try? HAL.readObjectList(id, addr)) ?? []
    }
}

// MARK: - Volume and mute

enum VolumeControl {

    /// Which volume elements on a given device are actually settable.
    /// Prefers the main element; falls back to the preferred stereo pair.
    static func volumeElements(for id: AudioObjectID) -> [AudioObjectPropertyElement] {
        let main = HAL.address(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        if HAL.has(id, main), HAL.isSettable(id, main) {
            return [kAudioObjectPropertyElementMain]
        }

        guard let channels = HAL.readStereoChannels(id) else { return [] }
        return channels.filter { element in
            let addr = HAL.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            return HAL.has(id, addr) && HAL.isSettable(id, addr)
        }
    }

    /// Average scalar volume (0...1) across every target the device drives.
    static func volume(of device: AudioDevice) -> Float? {
        var samples: [Float] = []

        for target in device.volumeTargets {
            for element in volumeElements(for: target) {
                let addr = HAL.address(
                    kAudioDevicePropertyVolumeScalar,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                )
                if let value = try? HAL.read(target, addr, as: Float32.self) {
                    samples.append(value)
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Float(samples.count)
    }

    /// Applies a scalar volume (0...1) to every target the device drives.
    @discardableResult
    static func setVolume(_ value: Float, on device: AudioDevice) -> Bool {
        let clamped = min(max(value, 0), 1)
        var appliedAny = false

        for target in device.volumeTargets {
            for element in volumeElements(for: target) {
                let addr = HAL.address(
                    kAudioDevicePropertyVolumeScalar,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                )
                if (try? HAL.write(target, addr, Float32(clamped))) != nil {
                    appliedAny = true
                }
            }
        }
        return appliedAny
    }

    static func isMuted(_ device: AudioDevice) -> Bool {
        for target in device.volumeTargets {
            let addr = HAL.address(
                kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput
            )
            if let muted = try? HAL.read(target, addr, as: UInt32.self), muted == 1 {
                return true
            }
        }
        return false
    }

    @discardableResult
    static func setMuted(_ muted: Bool, on device: AudioDevice) -> Bool {
        var appliedAny = false
        for target in device.volumeTargets {
            let addr = HAL.address(
                kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput
            )
            guard HAL.has(target, addr), HAL.isSettable(target, addr) else { continue }
            if (try? HAL.write(target, addr, UInt32(muted ? 1 : 0))) != nil {
                appliedAny = true
            }
        }
        return appliedAny
    }
}
