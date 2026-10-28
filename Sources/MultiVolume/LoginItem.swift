import Observation
import ServiceManagement

/// Whether the app opens at login, mirrored in System Settings > General >
/// Login Items.
@MainActor
@Observable
final class LoginItem {

    private(set) var isEnabled = false

    init() { refresh() }

    /// The user can change this in System Settings while the app runs, so
    /// re-read it whenever the menu opens.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MultiVolume: login item change failed: \(error)")
        }
        refresh()
    }
}
