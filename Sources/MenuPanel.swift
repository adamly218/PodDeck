import AppKit
import SwiftUI

/// Borderless panel that drops down from the menu bar icon and always stays
/// inside the visible part of the screen.
final class MenuPanel {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let panel: KeyPanel
    private let host: NSHostingView<DashboardView>
    private let makeView: (CGFloat) -> DashboardView
    private weak var anchor: NSStatusBarButton?
    private var clickMonitor: Any?

    var isShown: Bool { panel.isVisible }

    init(makeView: @escaping (CGFloat) -> DashboardView) {
        self.makeView = makeView
        host = NSHostingView(rootView: makeView(440))
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
    }

    func show(below button: NSStatusBarButton) {
        anchor = button
        layout()
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        panel.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// Sizes and places the panel under the icon, clamped to the screen.
    func layout() {
        guard let button = anchor, let buttonWindow = button.window else { return }
        let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(iconFrame) }) ?? NSScreen.main!
        let visible = screen.visibleFrame
        let top = min(iconFrame.minY, visible.maxY) - 6

        // Header + footer take about 130 pt; the device list gets what's left.
        let room = top - visible.minY - 12
        host.rootView = makeView(max(120, min(440, room - 130)))
        var size = host.fittingSize
        size.height = min(size.height, room)

        var x = iconFrame.midX - size.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}
