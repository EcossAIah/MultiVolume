import CoreAudio
import Foundation

// MARK: - Errors

enum AudioError: LocalizedError {
    case status(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case let .status(code, what):
            return "CoreAudio \(what) failed (OSStatus \(code))"
        }
    }
}

@inline(__always)
private func verify(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw AudioError.status(status, what) }
}

// MARK: - Thin, typed wrapper over the CoreAudio HAL
//
// All audio work goes through public CoreAudio APIs. No private frameworks.
// The only permission-gated code in the app lives in MediaKeyMonitor.swift.

enum HAL {

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        return AudioObjectHasProperty(id, &a)
    }

    static func isSettable(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &a, &settable) == noErr else { return false }
        return settable.boolValue
    }

    static func dataSize(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> UInt32 {
        var a = addr
        var size: UInt32 = 0
        try verify(AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size), "GetPropertyDataSize")
        return size
    }

    static func read<T>(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress, as type: T.Type = T.self) throws -> T {
        var a = addr
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { buffer.deallocate() }
        try verify(AudioObjectGetPropertyData(id, &a, 0, nil, &size, buffer), "GetPropertyData")
        return buffer.load(as: T.self)
    }

    static func write<T>(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) throws {
        var a = addr
        var v = value
        // Hand CoreAudio a properly formed raw buffer rather than taking the
        // address of a generic binding, which is only valid while T is
        // guaranteed to hold no object references.
        let status = withUnsafeBytes(of: &v) { raw -> OSStatus in
            AudioObjectSetPropertyData(
                id, &a, 0, nil, UInt32(MemoryLayout<T>.size), raw.baseAddress!
            )
        }
        try verify(status, "SetPropertyData")
    }

    static func readObjectList(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
        let size = try dataSize(id, addr)
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        var a = addr
        var s = size
        let status = ids.withUnsafeMutableBytes { raw -> OSStatus in
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, raw.baseAddress!)
        }
        try verify(status, "GetPropertyData(list)")
        return ids
    }

    /// Reads a CFString property without leaking the +1 reference CoreAudio hands back.
    static func readString(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> String {
        var a = addr
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanaged: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &a, 0, nil, &size, ptr)
        }
        try verify(status, "GetPropertyData(string)")
        guard let value = unmanaged else { return "" }
        return value.takeRetainedValue() as String
    }

    /// Reads a CFArray-of-CFString property, such as an aggregate's sub-device UIDs.
    static func readStringArray(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> [String] {
        var a = addr
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        var unmanaged: Unmanaged<CFArray>?
        let status = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &a, 0, nil, &size, ptr)
        }
        try verify(status, "GetPropertyData(array)")
        guard let value = unmanaged else { return [] }
        return value.takeRetainedValue() as? [String] ?? []
    }

    static func readStereoChannels(_ id: AudioObjectID) -> [AudioObjectPropertyElement]? {
        var a = address(
            kAudioDevicePropertyPreferredChannelsForStereo,
            scope: kAudioObjectPropertyScopeOutput
        )
        var channels: [UInt32] = [0, 0]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = channels.withUnsafeMutableBytes { raw -> OSStatus in
            AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw.baseAddress!)
        }
        return status == noErr ? channels : nil
    }
}

// MARK: - Property change listener with automatic teardown

/// Registers a CoreAudio property listener and removes it on deinit, so
/// listener lifetime is tied to object lifetime rather than manual bookkeeping.
final class PropertyListener {

    private let objectID: AudioObjectID
    private let address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock

    init?(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        self.objectID = objectID
        self.address = address
        self.queue = queue
        self.block = { _, _ in handler() }

        var a = address
        guard AudioObjectAddPropertyListenerBlock(objectID, &a, queue, block) == noErr else {
            return nil
        }
    }

    deinit {
        var a = address
        AudioObjectRemovePropertyListenerBlock(objectID, &a, queue, block)
    }
}
