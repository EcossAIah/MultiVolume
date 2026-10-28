import AppKit
import SwiftUI

/// An ⓘ glyph that shows its explanation the moment the pointer is over it,
/// fading in and out. Clicking it does nothing.
///
/// The system tooltip (`.help`) waits about a second before appearing, so this
/// draws its own, with the same tooltip material and font.
struct InfoTip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> InfoTipView {
        let view = InfoTipView()
        view.text = text
        return view
    }

    func updateNSView(_ view: InfoTipView, context: Context) {
        view.text = text
    }
}

final class InfoTipView: NSView {

    var text = ""
    private let glyph = NSImageView()
    private var tip: NSPanel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Secondary label colour: the standard grey for informational glyphs,
        // adapting to light and dark mode.
        glyph.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Info")?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular))
        glyph.contentTintColor = .secondaryLabelColor
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // Swallow clicks so the row underneath isn't selected.
    override func mouseDown(with event: NSEvent) {}

    override func mouseEntered(with event: NSEvent) { showTip() }
    override func mouseExited(with event: NSEvent) { hideTip() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { tip?.orderOut(nil) }
    }

    private func showTip() {
        guard let window, !text.isEmpty else { return }
        let panel = tip ?? makePanel()
        tip = panel

        let label = panel.contentView?.subviews.first?.subviews.first as? NSTextField
        label?.stringValue = text
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero

        // Below the glyph, right-aligned to it so it stays on screen at the
        // right edge where menu bar windows live.
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        var origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame {
            origin.x = max(screen.minX + 4, min(origin.x, screen.maxX - size.width - 4))
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func hideTip() {
        guard let panel = tip else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 240
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)

        let container = NSView()
        container.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -5),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])
        panel.contentView = container
        return panel
    }
}
