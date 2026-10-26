import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

// MARK: - Keys we care about

enum MediaKey {
    case volumeUp
    case volumeDown
    case mute
}

// Defined locally rather than relying on the IOKit macro import, so this does
// not silently break if those headers change.
private enum SystemDefined {
    static let eventType: UInt32 = 14        // NX_SYSDEFINED
    static let auxControlSubtype: Int16 = 8  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    static let soundUp: Int32 = 0            // NX_KEYTYPE_SOUND_UP
    static let soundDown: Int32 = 1          // NX_KEYTYPE_SOUND_DOWN
    static let mute: Int32 = 7               // NX_KEYTYPE_MUTE
}

/// Why the event tap could not be installed. Reported in the UI so a missing
/// permission never looks like a broken app.
enum MediaKeyFailure: Equatable {
    case accessibilityMissing
    case inputMonitoringMissing
    case tapRefused

    var summary: String {
        switch self {
        case .accessibilityMissing: return "Accessibility permission needed"
        case .inputMonitoringMissing: return "Input Monitoring permission needed"
        case .tapRefused: return "macOS refused the event tap"
        }
    }

    var detail: String {
        switch self {
        case .accessibilityMissing:
            return "Grant it, then this will switch on by itself."
        case .inputMonitoringMissing:
            return "Media keys are HID events; macOS gates them behind this."
        case .tapRefused:
            return "Both permissions look granted. If this app was rebuilt, remove its entries in Privacy & Security and grant again — the code signature changed."
        }
    }
}

// MARK: - Event tap

/// Intercepts the hardware volume keys (F10/F11/F12).
///
/// SECURITY NOTE. This is the only part of the app that needs privacy
/// permissions. macOS delivers these keys as system-defined HID events, and
/// the only way to observe them is a `CGEventTap`. There is no permission-free
/// alternative for these specific keys.
///
/// What this implementation does to limit the blast radius:
///   * The tap subscribes only to `NX_SYSDEFINED`. Ordinary key events are not
///     in `eventsOfInterest`, so no typed text is ever delivered here.
///   * Events are passed through untouched unless the current output device is
///     an aggregate, where the system's own handling is a no-op anyway.
///   * Nothing is logged, stored, or transmitted.
///   * Built with hardened runtime and without `get-task-allow`, so the
///     granted permission cannot be borrowed by another local process.
final class MediaKeyMonitor {

    /// `(key, isPressed, isRepeat) -> shouldConsumeEvent`
    typealias Handler = (MediaKey, Bool, Bool) -> Bool

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var lastFailure: MediaKeyFailure?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    var isRunning: Bool { eventTap != nil }

    // MARK: Permissions

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Media keys are HID events. Since macOS 10.15 observing them through an
    /// event tap is governed by Input Monitoring, which is a *separate* grant
    /// from Accessibility — granting one does not imply the other.
    static var hasInputMonitoringPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    static func requestInputMonitoringPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            lastFailure = nil
            return true
        }

        let mask = CGEventMask(1 << SystemDefined.eventType)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Attempt first, diagnose second. Which permission macOS actually
        // demands for this tap has varied across releases, so the honest
        // answer comes from trying rather than from guessing up front.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: refcon
        ) else {
            if !Self.hasAccessibilityPermission {
                lastFailure = .accessibilityMissing
            } else if !Self.hasInputMonitoringPermission {
                lastFailure = .inputMonitoringMissing
            } else {
                lastFailure = .tapRefused
            }
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        lastFailure = nil
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: Event handling

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        // macOS disables a tap that takes too long, or when the user forces it
        // off. Re-arm rather than silently dying.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }

        guard type.rawValue == SystemDefined.eventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == SystemDefined.auxControlSubtype
        else { return passThrough }

        guard let decoded = MediaKeyEvent(data1: nsEvent.data1) else { return passThrough }

        // The handler decides whether we own this key press. Both the down and
        // the up event are consumed together so the system never sees half an
        // event.
        let consume = handler(decoded.key, decoded.isPressed, decoded.isRepeat)
        return consume ? nil : passThrough
    }
}

// MARK: - Decoding

/// A volume key press decoded from the `data1` field of an
/// `NX_SUBTYPE_AUX_CONTROL_BUTTONS` event.
///
/// Layout: bits 16-31 hold the key code, bits 8-15 the key state
/// (0x0A down, 0x0B up), and bit 0 the repeat flag.
struct MediaKeyEvent: Equatable {
    let key: MediaKey
    let isPressed: Bool
    let isRepeat: Bool

    /// Returns `nil` for any key other than volume up, volume down or mute.
    init?(data1 data: Int) {
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let flags = data & 0x0000_FFFF

        switch keyCode {
        case SystemDefined.soundUp: key = .volumeUp
        case SystemDefined.soundDown: key = .volumeDown
        case SystemDefined.mute: key = .mute
        default: return nil
        }
        isPressed = ((flags & 0xFF00) >> 8) == 0x0A
        isRepeat = (flags & 0x1) == 1
    }
}

// C callback: no captures allowed, so state travels through `userInfo`.
private let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.process(type: type, event: event)
}
