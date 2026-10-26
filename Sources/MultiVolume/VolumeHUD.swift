import AppKit
import Observation
import SwiftUI

/// On-screen volume indicator shown when the volume keys are pressed.
///
/// macOS only draws its own HUD when it handles the key itself. For aggregate
/// devices this app consumes the key, so the system HUD never appears and we
/// draw a look-alike instead. The system HUD is private API; this is not.
@MainActor
final class VolumeHUD {

    @Observable
    final class State {
        var level: Double = 0
        var isMuted = false
        var deviceName = ""
    }

    private let state = State()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private static let size = NSSize(width: 300, height: 64)
    private static let visibleFor: TimeInterval = 1.5

    func show(level: Double, isMuted: Bool, deviceName: String) {
        state.level = level
        state.isMuted = isMuted
        state.deviceName = deviceName

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)

        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A key press during the fade brings it back to full opacity.
                guard let panel = self?.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: VolumeHUDView(state: state))
        return panel
    }

    /// Top-right corner, just under the menu bar, on the screen the pointer is on
    /// — where macOS itself puts the volume indicator.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let origin = NSPoint(
            x: visible.maxX - Self.size.width - margin,
            y: visible.maxY - Self.size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

private struct VolumeHUDView: View {
    let state: VolumeHUD.State

    private var iconName: String {
        if state.isMuted { return "speaker.slash.fill" }
        switch state.level {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.deviceName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.primary)
                            .frame(width: geo.size.width * (state.isMuted ? 0 : state.level))
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.12), value: state.level)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
