import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: DeviceStore
    @ObservedObject var audio: AudioInputLock
    let previewHUD: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            hud.tabItem { Label("HUD", systemImage: "rectangle.topthird.inset.filled") }
            alerts.tabItem { Label("Alerts", systemImage: "bell") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
        .padding()
    }

    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin },
                                                    set: { settings.launchAtLogin = $0 }))
            Toggle("Show lowest headset battery in the menu bar", isOn: $settings.menuBarPercent)
            Toggle("Show desktop widget", isOn: $settings.showWidget)
            Section("Audio Input Lock") {
                Toggle("Keep this microphone selected", isOn: $settings.inputLockEnabled)
                Picker("Microphone", selection: $settings.inputLockUID) {
                    Text("None").tag("")
                    ForEach(audio.inputs) { Text($0.name).tag($0.uid) }
                }
                Text("Stops macOS from switching to your headset's mic when it connects, which keeps audio in high quality.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hud: some View {
        Form {
            Picker("Position", selection: $settings.hudPosition) {
                ForEach(HUDPosition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Style", selection: $settings.hudStyle) {
                ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show when AirPods are nearby and not connected", isOn: $settings.hudOnCaseOpen)
            Toggle("Show when a headset connects", isOn: $settings.hudOnConnect)
            Button("Preview HUD", action: previewHUD)
        }
        .formStyle(.grouped)
    }

    private var alerts: some View {
        Form {
            Stepper("Low battery alert at \(settings.lowThreshold)%", value: $settings.lowThreshold, in: 5...50, step: 5)
            Picker("Alert style", selection: $settings.alertStyle) {
                ForEach(AlertStyle.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Alert when a device finishes charging", isOn: $settings.notifyFullCharge)
            Section("Alerts per device") {
                ForEach(store.devices) { device in
                    Toggle(device.name, isOn: Binding(get: { !settings.mutedAlertIDs.contains(device.id) },
                                                      set: { _ in settings.toggleMuted(device.id) }))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("PodDeck").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundColor(.secondary)
            Text("Batteries, connections and controls for AirPods, Beats and Apple accessories.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Text("© 2026 adamly218 · MIT License").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
