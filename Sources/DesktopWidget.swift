import AppKit
import Combine
import SwiftUI

/// A batteries widget that sits on the desktop, below normal windows. Drag it anywhere.
final class DesktopWidgetController {
    private let store: DeviceStore
    private var window: NSPanel?
    private var subscription: AnyCancellable?

    init(store: DeviceStore) {
        self.store = store
        subscription = Settings.shared.$widgetSize.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fitToContent() }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            let window = self.window ?? makeWindow()
            self.window = window
            window.orderFrontRegardless()
            fitToContent()
        } else {
            window?.orderOut(nil)
        }
    }

    /// Resizes around the top-left corner so the widget doesn't jump when its size changes.
    private func fitToContent() {
        guard let window, let content = window.contentView else { return }
        let size = WidgetView.size(for: Settings.shared.widgetSize)
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - size.height, width: size.width, height: size.height),
                        display: true)
        content.frame = NSRect(origin: .zero, size: size)
    }

    private func makeWindow() -> NSPanel {
        let size = WidgetView.size(for: Settings.shared.widgetSize)
        let panel = NSPanel(contentRect: NSRect(x: 80, y: 600, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        let host = WidgetHostingView(rootView: WidgetView(store: store, settings: .shared))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrameAutosaveName("PodDeckDesktopWidget")
        return panel
    }
}

/// Takes every click on the widget (it has no buttons) and drags the window with it.
/// Without this the blur view underneath swallows the click and nothing moves.
final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// One ring or row in the widget: a device, or the case of a pair of earbuds.
struct WidgetEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let level: Int
    let charging: Bool
}

struct WidgetView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var settings: Settings
    @Environment(\.colorScheme) private var colorScheme

    static func size(for size: WidgetSize) -> CGSize {
        switch size {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large: return CGSize(width: 364, height: 382)
        }
    }

    private var entries: [WidgetEntry] {
        var out: [WidgetEntry] = []
        for d in store.devices where !d.battery.isEmpty {
            let b = d.battery
            let worn = [b.main, b.left, b.right].compactMap { $0 }
            if let level = worn.min() {
                out.append(WidgetEntry(id: d.id, name: d.name, symbol: d.symbol, level: level,
                                       charging: b.mainCharging || b.leftCharging || b.rightCharging))
            }
            if let level = b.caseLevel {
                let caseSymbol = d.symbol.hasPrefix("airpodspro") ? "airpodspro.chargingcase.wireless.fill"
                    : d.symbol.hasPrefix("airpods") ? "airpods.chargingcase.fill" : "case.fill"
                out.append(WidgetEntry(id: d.id + "-case", name: "Case", symbol: caseSymbol, level: level,
                                       charging: b.caseCharging))
            }
        }
        return out
    }

    var body: some View {
        let size = Self.size(for: settings.widgetSize)
        Group {
            switch settings.widgetSize {
            case .small: ringGrid(columns: 2, rows: 2, ring: 56)
            case .medium: ringGrid(columns: 4, rows: 1, ring: 64)
            case .large: list
            }
        }
        .frame(width: size.width, height: size.height)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.35), lineWidth: 0.5))
    }

    private var background: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, cornerRadius: 24)
            (colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
        }
    }

    // MARK: Small and medium: rings

    private func ringGrid(columns: Int, rows: Int, ring: CGFloat) -> some View {
        let slots = columns * rows
        let shown = Array(entries.prefix(slots))
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        WidgetRing(entry: index < shown.count ? shown[index] : nil, diameter: ring)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(rows == 1 ? 14 : 10)
    }

    // MARK: Large: list with bars

    private var list: some View {
        let shown = Array(entries.prefix(6))
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    WidgetRing(entry: index < shown.count ? shown[index] : nil, diameter: 52, showLabel: false)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 14)
            VStack(spacing: 11) {
                ForEach(shown) { WidgetRow(entry: $0) }
                if shown.isEmpty {
                    Text("No battery readings yet").font(.system(size: 13)).foregroundColor(.secondary)
                        .padding(.top, 20)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private let ringGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
private let ringRed = Color(red: 1.0, green: 0.27, blue: 0.23)

private func ringColor(_ entry: WidgetEntry) -> Color {
    entry.level <= 20 && !entry.charging ? ringRed : ringGreen
}

struct WidgetRing: View {
    let entry: WidgetEntry?
    let diameter: CGFloat
    var showLabel = true

    var body: some View {
        let line = diameter * 0.09
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.14), lineWidth: line)
                if let entry {
                    Circle()
                        .trim(from: 0, to: max(0.02, CGFloat(entry.level) / 100))
                        .stroke(ringColor(entry), style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: entry.symbol)
                        .font(.system(size: diameter * 0.34, weight: .regular))
                        .foregroundColor(.primary)
                    if entry.charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: diameter * 0.16, weight: .bold))
                            .foregroundColor(ringGreen)
                            .padding(diameter * 0.04)
                            .background(Circle().fill(.background))
                            .offset(y: -diameter / 2)
                    }
                }
            }
            .padding(line / 2)
            .frame(width: diameter, height: diameter)

            if showLabel {
                Text(entry.map { "\($0.level)%" } ?? " ")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
        }
    }
}

struct WidgetRow: View {
    let entry: WidgetEntry?

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                if let entry {
                    Image(systemName: entry.symbol).font(.system(size: 13)).frame(width: 18)
                    Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if entry.charging {
                        Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)).foregroundColor(ringGreen)
                    }
                    Spacer(minLength: 6)
                    Text("\(entry.level)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                } else {
                    Text(" ").font(.system(size: 13))
                    Spacer()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if let entry {
                        Capsule().fill(ringColor(entry))
                            .frame(width: max(4, geo.size.width * CGFloat(entry.level) / 100))
                    }
                }
            }
            .frame(height: 4)
        }
    }
}
