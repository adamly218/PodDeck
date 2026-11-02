import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var settings: Settings
    @ObservedObject var audio: AudioInputLock
    let openSettings: () -> Void
    let showHUD: (String) -> Void
    var maxListHeight: CGFloat = 440

    private var mainDevices: [Device] {
        store.devices.filter { $0.isConnected || $0.kind == .mac || settings.pinnedIDs.contains($0.id) || !$0.battery.isEmpty }
    }

    private var otherDevices: [Device] {
        let shown = Set(mainDevices.map(\.id))
        return store.devices.filter { !shown.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PodDeck").font(.headline)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
                Button(action: { NSApp.terminate(nil) }) { Image(systemName: "power") }
                    .buttonStyle(.borderless).help("Quit PodDeck")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    if mainDevices.isEmpty {
                        Text("No devices yet.\nPair AirPods or accessories in System Settings → Bluetooth.")
                            .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                            .padding(.vertical, 30)
                    }
                    ForEach(mainDevices) { row($0) }
                    if !otherDevices.isEmpty {
                        Text("OTHER PAIRED DEVICES")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8).padding(.leading, 4)
                        ForEach(otherDevices) { row($0) }
                    }
                }
                .padding(10)
            }
            .frame(height: min(maxListHeight, CGFloat(store.devices.count) * 58 + (otherDevices.isEmpty ? 30 : 60) + (mainDevices.isEmpty ? 80 : 0)))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Audio Input Lock", isOn: $settings.inputLockEnabled).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Picker("", selection: $settings.inputLockUID) {
                        Text("Choose mic").tag("")
                        ForEach(audio.inputs) { Text($0.name).tag($0.uid) }
                    }
                    .labelsHidden().frame(width: 150).controlSize(.small)
                }
                Toggle("Desktop widget", isOn: $settings.showWidget).toggleStyle(.switch).controlSize(.small)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.12)))
    }

    private func row(_ device: Device) -> some View {
        DeviceRow(device: device, busy: store.busyIDs.contains(device.id),
                  pinned: settings.pinnedIDs.contains(device.id),
                  muted: settings.mutedAlertIDs.contains(device.id),
                  toggleConnection: { store.setConnected(!device.isConnected, device) },
                  togglePin: { settings.togglePinned(device.id) },
                  toggleMute: { settings.toggleMuted(device.id) },
                  showHUD: { showHUD(device.id) })
    }
}

struct DeviceRow: View {
    let device: Device
    let busy: Bool
    let pinned: Bool
    let muted: Bool
    let toggleConnection: () -> Void
    let togglePin: () -> Void
    let toggleMute: () -> Void
    let showHUD: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DeviceIcon(symbol: device.symbol, size: 34)
                .foregroundColor(device.isConnected ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundColor(.secondary) }
                }
                if device.battery.isEmpty {
                    Text(device.statusText).font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) { ForEach(device.battery.parts) { BatteryPill(part: $0) } }
                }
            }
            Spacer(minLength: 4)
            if device.canConnect {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(device.isConnected ? "Disconnect" : "Connect", action: toggleConnection)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin to top", action: togglePin)
            Button(muted ? "Turn on battery alerts" : "Turn off battery alerts", action: toggleMute)
            Button("Show in HUD", action: showHUD)
        }
    }
}
