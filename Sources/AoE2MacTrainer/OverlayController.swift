import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: NSPanel

    init(state: TrainerState) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 350),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let view = NSHostingView(rootView: OverlayView(state: state))
        view.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 350, height: 350)
        panel.contentView = view
        moveToUpperRight()
    }

    private func moveToUpperRight() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - 22,
            y: frame.maxY - panel.frame.height - 45
        ))
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        moveToUpperRight()
        panel.orderFrontRegardless()
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }
}
