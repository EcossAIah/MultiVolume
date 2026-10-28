import SwiftUI

@main
struct MultiVolumeApp: App {

    // SwiftUI creates the App value once, so a plain stored property is
    // enough. It also avoids the @State macro, whose compiler plugin is not
    // shipped with the Command Line Tools for recent SDKs.
    private let manager = AudioManager()
    private let loginItem = LoginItem()
    private let editor = MultiOutputEditor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(manager: manager, loginItem: loginItem, editor: editor)
        } label: {
            MenuBarLabel(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon. A separate view so its body is observation-tracked and
/// redraws when the volume or mute state changes.
private struct MenuBarLabel: View {
    let manager: AudioManager

    var body: some View {
        Image(systemName: manager.iconName)
            .accessibilityLabel("Volume")
    }
}
