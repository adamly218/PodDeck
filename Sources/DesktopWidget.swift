import AppKit
import SwiftUI

/// A battery board that sits on the desktop, below normal windows. Drag it anywhere.
final class DesktopWidgetController {
    private let store: DeviceStore
    private var window: NSPanel?

    init(store: DeviceStore) {
        self.store = store
    }

    func setVisible(_ visible: Bool) {
        if visible {
            let window = self.window ?? makeWindow()
            self.window = window
            window.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 80, y: 80, width: 320, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = DraggableHostingView(rootView: WidgetView(store: store))
        panel.setFrameAutosaveName("PodDeckDesktopWidget")
        return panel
    }
}

struct WidgetView: View {
    @ObservedObject var store: DeviceStore

    private var devices: [Device] { store.devices.filter { !$0.battery.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batteries").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            if devices.isEmpty {
                Text("No battery readings yet").font(.callout).foregroundColor(.secondary)
            }
            ForEach(devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: device.symbol).font(.system(size: 16)).frame(width: 24)
                    Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    ForEach(device.battery.parts) { BatteryRing(part: $0, size: 30) }
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
