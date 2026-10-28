import AppKit

/// The "pop" macOS plays when the volume keys are pressed.
///
/// It plays through the default output, so its loudness tracks the new volume
/// on its own. Like the system, it only plays when "Play feedback when volume
/// is changed" is on in Sound settings.
@MainActor
final class VolumeFeedback {

    private static let soundPath =
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"

    private lazy var sound = NSSound(contentsOfFile: Self.soundPath, byReference: true)

    private var isEnabled: Bool {
        // Unset means on, which is the system default.
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[
            "com.apple.sound.beep.feedback"
        ] as? Int != 0
    }

    func play() {
        guard isEnabled, let sound else { return }
        // Restart on rapid presses instead of skipping, as the system does.
        sound.stop()
        sound.play()
    }
}
