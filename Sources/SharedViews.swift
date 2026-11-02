import SwiftUI

func batteryColor(_ level: Int, charging: Bool) -> Color {
    if charging { return .green }
    if level <= 10 { return .red }
    if level <= 20 { return .orange }
    return .green
}

struct BatteryRing: View {
    let part: BatteryPart
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: size * 0.1)
                Circle()
                    .trim(from: 0, to: CGFloat(part.level) / 100)
                    .stroke(batteryColor(part.level, charging: part.charging),
                            style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if part.charging {
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.3)).foregroundColor(.green)
                } else {
                    Text("\(part.level)").font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: size, height: size)
            Text(part.label.isEmpty ? "\(part.level)%" : "\(part.label) \(part.level)%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

struct BatteryPill: View {
    let part: BatteryPart

    var body: some View {
        HStack(spacing: 3) {
            if !part.label.isEmpty {
                Text(part.label).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).fill(Color.primary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(batteryColor(part.level, charging: part.charging))
                    .frame(width: max(2, 20 * CGFloat(part.level) / 100))
            }
            .frame(width: 20, height: 9)
            Text(part.charging ? "\(part.level)%⚡︎" : "\(part.level)%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct DeviceIcon: View {
    let symbol: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(0.08)))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Hosting view that lets the window be dragged from anywhere.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}
