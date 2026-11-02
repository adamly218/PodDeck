import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let store = DeviceStore()
    private let audio = AudioInputLock()
    private var statusItem: NSStatusItem!
    private var menu: MenuPanel!
    private var hud: HUDController!
    private var widget: DesktopWidgetController!
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        hud = HUDController(store: store)
        widget = DesktopWidgetController(store: store)
        store.onHUD = { [weak self] in self?.hud.show($0) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading
        updateStatusItem()

        menu = MenuPanel { [unowned self] maxListHeight in
            DashboardView(store: store, settings: settings, audio: audio,
                          openSettings: { [weak self] in self?.openSettings() },
                          showHUD: { [weak self] in self?.hud.show(.connected($0)) },
                          maxListHeight: maxListHeight)
        }

        store.$devices.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateStatusItem()
            if self?.menu.isShown == true { self?.menu.layout() }
        }
            .store(in: &subscriptions)
        settings.$menuBarPercent.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        settings.$showWidget.receive(on: DispatchQueue.main).sink { [weak self] in self?.widget.setVisible($0) }
            .store(in: &subscriptions)
        settings.$inputLockEnabled.combineLatest(settings.$inputLockUID).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.audio.enforce() }
            .store(in: &subscriptions)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        store.start()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let headset = store.devices.first { $0.kind == .headset && $0.isConnected }
        let image = NSImage(systemSymbolName: headset?.symbol ?? "airpodspro", accessibilityDescription: "PodDeck")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "PodDeck")
        image?.isTemplate = true
        button.image = image
        if settings.menuBarPercent, let level = headset?.battery.lowest {
            button.title = " \(level)%"
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if menu.isShown {
            menu.close()
        } else {
            menu.show(below: button)
        }
    }

    private func openSettings() {
        menu.close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "PodDeck Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(
                settings: settings, store: store, audio: audio,
                previewHUD: { [weak self] in self?.previewHUD() }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func previewHUD() {
        let device = store.devices.first { $0.kind == .headset } ?? store.devices.first
        if let device { hud.show(.connected(device.id)) }
    }
}

/// `PodDeck --dump`: scan for a few seconds and print what was found.
if CommandLine.arguments.contains("--dump") {
    let store = DeviceStore()
    store.start()
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    for d in store.devices {
        let parts = d.battery.parts.map { "\($0.label.isEmpty ? "" : $0.label + " ")\($0.level)%\($0.charging ? "⚡" : "")" }
        print("\(d.name) [\(d.kind)] \(d.statusText)\(d.modelName.map { " · " + $0 } ?? "")  \(parts.joined(separator: "  "))")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
