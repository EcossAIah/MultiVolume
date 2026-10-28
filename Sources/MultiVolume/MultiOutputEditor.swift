import CoreAudio
import Observation

/// State for the in-menu multi-output editor. A class rather than view
/// `@State`, which needs a compiler plugin the Command Line Tools lack.
@MainActor
@Observable
final class MultiOutputEditor {

    enum Mode: Equatable {
        case closed
        case creating
        case editing(AudioDevice)
    }

    private(set) var mode: Mode = .closed
    var name = ""
    /// Sub-device UIDs, in the order they were ticked. The first is the clock.
    private(set) var selection: [String] = []
    private(set) var errorMessage: String?
    var confirmingDelete = false

    var isOpen: Bool { mode != .closed }

    var canSave: Bool {
        selection.count >= 2 && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func startCreating() {
        mode = .creating
        name = "Multi-Output Device"
        selection = []
        errorMessage = nil
    }

    func startEditing(_ device: AudioDevice) {
        mode = .editing(device)
        name = device.name
        selection = MultiOutputDevices.subDeviceUIDs(of: device.id)
        errorMessage = nil
    }

    func close() {
        mode = .closed
        confirmingDelete = false
        errorMessage = nil
    }

    func isSelected(_ device: AudioDevice) -> Bool { selection.contains(device.uid) }

    func toggle(_ device: AudioDevice) {
        if let index = selection.firstIndex(of: device.uid) {
            selection.remove(at: index)
        } else {
            selection.append(device.uid)
        }
    }

    func save(using manager: AudioManager) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .closed:
                return
            case .creating:
                try manager.createMultiOutput(name: trimmed, subDeviceUIDs: selection)
            case let .editing(device):
                try manager.updateMultiOutput(device, name: trimmed, subDeviceUIDs: selection)
            }
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ device: AudioDevice, using manager: AudioManager) {
        do {
            try manager.deleteMultiOutput(device)
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
