import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: NSPanel
    private var hostingView: NSHostingView<OverlayView>?
    private var stateObservation: AnyCancellable?

    init(state: TrainerState) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 390),
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
        view.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 350, height: 390)
        panel.contentView = view
        hostingView = view
        stateObservation = state.objectWillChange.sink { [weak self] in
            // objectWillChange fires before the new published value is stored.
            // Fit on the next main-loop turn, after SwiftUI updates its content.
            DispatchQueue.main.async { self?.fitContent() }
        }
        fitContent()
    }

    private func fitContent() {
        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 100
        let height = min(max(hostingView.fittingSize.height, 220), availableHeight)
        panel.setContentSize(NSSize(width: 350, height: height))
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
        fitContent()
        panel.orderFrontRegardless()
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }
}
