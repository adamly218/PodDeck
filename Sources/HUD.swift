import AppKit
import SwiftUI

final class HUDController {
    private let store: DeviceStore
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    init(store: DeviceStore) {
        self.store = store
    }

    func show(_ event: HUDEvent) {
        guard store.device(event.deviceID) != nil else { return }
        let view = HUDView(store: store, settings: .shared, event: event, close: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        panel.setFrame(frame(for: size), display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        let seconds: Double
        if case .nearby = event { seconds = 10 } else { seconds = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func frame(for size: NSSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let y = visible.maxY - size.height - 12
        let x: CGFloat
        switch Settings.shared.hudPosition {
        case .left: x = visible.minX + 16
        case .center: x = visible.midX - size.width / 2
        case .right: x = visible.maxX - size.width - 16
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct HUDView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var settings: Settings
    let event: HUDEvent
    let close: () -> Void

    private var compact: Bool { settings.hudStyle == .compact }

    private var subtitle: String {
        switch event {
        case .nearby: return "Nearby · Ready to connect"
        case .connected: return "Connected"
        case .lowBattery(_, let level): return "Low battery · \(level)%"
        case .charged: return "Fully charged"
        }
    }

    var body: some View {
        let device = store.device(event.deviceID)
        HStack(spacing: compact ? 10 : 14) {
            DeviceIcon(symbol: device?.symbol ?? "headphones", size: compact ? 34 : 50)
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device?.name ?? "Device").font(.system(size: compact ? 13 : 15, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: compact ? 11 : 12))
                        .foregroundColor(isWarning ? .orange : .secondary)
                }
                if let device, !device.battery.isEmpty {
                    if compact {
                        HStack(spacing: 8) { ForEach(device.battery.parts) { BatteryPill(part: $0) } }
                    } else {
                        HStack(spacing: 14) { ForEach(device.battery.parts) { BatteryRing(part: $0, size: 38) } }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.borderless).foregroundColor(.secondary)
                if let device, device.canConnect {
                    if store.busyIDs.contains(device.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(device.isConnected ? "Disconnect" : "Connect") {
                            store.setConnected(!device.isConnected, device)
                        }
                        .controlSize(compact ? .small : .regular)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(compact ? 12 : 16)
        .frame(width: compact ? 320 : 400)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous))
    }

    private var isWarning: Bool {
        if case .lowBattery = event { return true }
        return false
    }
}
