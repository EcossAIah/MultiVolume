import AppKit
import Observation
import SwiftUI

/// On-screen volume indicator shown when the volume keys are pressed.
///
/// macOS only draws its own HUD when it handles the key itself. For aggregate
/// devices this app consumes the key, so the system HUD never appears and we
/// draw a look-alike instead. The system HUD is private API; this is not.
///
/// Like the system one, hovering turns the bar into a slider, and the speaker
/// icons on either end mute or max out the volume.
@MainActor
final class VolumeHUD {

    @Observable
    final class State {
        var level: Double = 0
        var isMuted = false
        var deviceName = ""
        var isHovered = false
    }

    /// Called when the slider is dragged.
    var onSetVolume: ((Double) -> Void)?
    /// Called when the left speaker icon is clicked.
    var onMute: (() -> Void)?
    /// Called when the right speaker icon is clicked.
    var onMaximize: (() -> Void)?

    private let state = State()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// Includes `inset` on every side, room for the close button to overhang
    /// the glass the way the system one does.
    private static let size = NSSize(width: 300, height: 80)
    fileprivate static let inset: CGFloat = 8
    fileprivate static let cornerRadius: CGFloat = 22
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

        scheduleHide()
    }

    /// Refreshes the HUD after a change made from inside it, without moving it.
    func update(level: Double, isMuted: Bool) {
        state.level = level
        state.isMuted = isMuted
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        // Stay up while the pointer is over the HUD; leaving restarts the timer.
        guard !state.isHovered else { return }
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    private func setHovered(_ hovered: Bool) {
        state.isHovered = hovered
        if hovered, let panel, panel.alphaValue < 1 {
            // Caught mid-fade: bring it back.
            panel.alphaValue = 1
        }
        scheduleHide()
    }

    private func dismiss() {
        hideWork?.cancel()
        state.isHovered = false
        fadeOut()
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
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = VolumeHUDView(
            state: state,
            setVolume: { [weak self] in self?.onSetVolume?($0) },
            mute: { [weak self] in self?.onMute?() },
            maximize: { [weak self] in self?.onMaximize?() },
            close: { [weak self] in self?.dismiss() }
        )
        let host = HUDHostingView(rootView: view)
        host.onHover = { [weak self] in self?.setHovered($0) }
        panel.contentView = host
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
        let margin: CGFloat = 12 - Self.inset
        let origin = NSPoint(
            x: visible.maxX - Self.size.width - margin,
            y: visible.maxY - Self.size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

/// Hosts the HUD content. The panel never becomes key and this app is never
/// active, so hover tracking has to be `.activeAlways` and the first click has
/// to go straight through to the controls.
private final class HUDHostingView<Content: View>: NSHostingView<Content> {

    var onHover: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

private struct VolumeHUDView: View {
    let state: VolumeHUD.State
    let setVolume: (Double) -> Void
    let mute: () -> Void
    let maximize: () -> Void
    let close: () -> Void

    private var shownLevel: Double { state.isMuted ? 0 : state.level }

    private var levelBinding: Binding<Double> {
        Binding(get: { shownLevel }, set: { setVolume($0) })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .hudBackground()
                .padding(VolumeHUD.inset)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            if state.isHovered {
                closeButton.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: state.isHovered)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.deviceName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                iconButton(state.isMuted ? "speaker.slash.fill" : "speaker.fill", help: "Mute", action: mute)

                ZStack {
                    if state.isHovered {
                        Slider(value: levelBinding, in: 0...1)
                            .labelsHidden()
                            .tint(.white)
                    } else {
                        bar
                    }
                }
                .frame(height: 20)

                iconButton("speaker.wave.3.fill", help: "Maximum volume", action: maximize)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The resting look: a white line over a dotted scale, like the system HUD.
    private var bar: some View {
        GeometryReader { geo in
            let dots = max(Int(geo.size.width / 6), 2)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dots, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.45))
                            .frame(width: 2, height: 2)
                        if index < dots - 1 { Spacer(minLength: 0) }
                    }
                }
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * shownLevel, height: 3)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.12), value: shownLevel)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .frame(width: 16, height: 16)
                .closeButtonBackground()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

private extension View {
    @ViewBuilder
    func closeButtonBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Circle())
        } else {
            background(.gray.opacity(0.85), in: Circle())
        }
    }

    /// Clear Liquid Glass where the OS has it, frosted material before that.
    @ViewBuilder
    func hudBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .clear,
                in: RoundedRectangle(cornerRadius: VolumeHUD.cornerRadius, style: .continuous)
            )
        } else {
            background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: VolumeHUD.cornerRadius, style: .continuous)
            )
        }
    }
}
