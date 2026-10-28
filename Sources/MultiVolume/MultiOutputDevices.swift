import CoreAudio
import Foundation

/// Creates, rebuilds and deletes multi-output devices — what Audio MIDI Setup
/// does with "Create Multi-Output Device", through the same public API.
///
/// The devices are public, so they appear in the Sound menu and Audio MIDI
/// Setup and keep working after this app quits.
enum MultiOutputDevices {

    /// UIDs of every sub-device, in order, active or not.
    static func subDeviceUIDs(of id: AudioObjectID) -> [String] {
        let addr = HAL.address(kAudioAggregateDevicePropertyFullSubDeviceList)
        return (try? HAL.readStringArray(id, addr)) ?? []
    }

    /// The first device is the clock source; the rest are drift-corrected
    /// against it, as Audio MIDI Setup does by default.
    static func create(name: String, uid: String? = nil, subDeviceUIDs: [String]) throws -> AudioObjectID {
        guard let main = subDeviceUIDs.first else {
            throw AudioError.status(OSStatus(kAudioHardwareIllegalOperationError), "CreateAggregateDevice")
        }
        let subDevices: [[String: Any]] = subDeviceUIDs.map { subUID in
            [
                kAudioSubDeviceUIDKey: subUID,
                kAudioSubDeviceDriftCompensationKey: subUID == main ? 0 : 1
            ]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid ?? "io.github.ecossaiah.multivolume.\(UUID().uuidString)",
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey: main,
            kAudioAggregateDeviceIsStackedKey: 1,  // multi-output, not aggregate
            kAudioAggregateDeviceIsPrivateKey: 0
        ]

        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id != kAudioObjectUnknown else {
            throw AudioError.status(status, "CreateAggregateDevice")
        }
        return id
    }

    static func destroy(_ id: AudioObjectID) throws {
        let status = AudioHardwareDestroyAggregateDevice(id)
        guard status == noErr else { throw AudioError.status(status, "DestroyAggregateDevice") }
    }

    /// Changes which devices it plays to. CoreAudio has no simple way to
    /// redo the drift settings in place, so it is recreated under the same UID
    /// — which keeps the saved balance and the Sound menu entry.
    static func rebuild(_ device: AudioDevice, name: String, subDeviceUIDs: [String]) throws -> AudioObjectID {
        try destroy(device.id)
        return try create(name: name, uid: device.uid, subDeviceUIDs: subDeviceUIDs)
    }
}
