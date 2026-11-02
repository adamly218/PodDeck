import Foundation
import UserNotifications

enum HUDEvent {
    case nearby(String)
    case connected(String)
    case lowBattery(String, Int)
    case charged(String)

    var deviceID: String {
        switch self {
        case .nearby(let id), .connected(let id), .lowBattery(let id, _), .charged(let id): return id
        }
    }
}

final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var busyIDs: Set<String> = []

    var onHUD: ((HUDEvent) -> Void)?

    private let settings = Settings.shared
    private let scanner = AirPodsScanner()
    private var paired: [PairedDevice] = []
    private var profiler: [String: ProfilerEntry] = [:]
    private var accessories: [AccessoryBattery] = []
    private var mac: Battery?
    private var mobiles: [MobileDevice] = []
    private var readings: [Int: HeadsetReading] = [:]
    private var lastNearbyHUD: [Int: Date] = [:]
    private var lowAlerted: Set<String> = []
    private var fullAlerted: Set<String> = []
    private var connectedIDs: Set<String> = []
    private var lastRebuild = Date.distantPast
    private let launchDate = Date()
    private var timers: [Timer] = []

    func start() {
        scanner.onReading = { [weak self] in self?.handle($0) }
        scanner.start()
        refresh()
        refreshProfiler()
        refreshMobiles()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() },
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refreshProfiler() },
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshMobiles() },
        ]
    }

    func device(_ id: String) -> Device? { devices.first { $0.id == id } }

    // MARK: Actions

    func setConnected(_ connect: Bool, _ device: Device) {
        guard device.canConnect, let address = device.address, !busyIDs.contains(device.id) else { return }
        busyIDs.insert(device.id)
        BluetoothDevices.setConnected(connect, address: address) { [weak self] _ in
            guard let self else { return }
            self.busyIDs.remove(device.id)
            self.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.refreshProfiler() }
        }
    }

    // MARK: Sources

    private func refresh() {
        paired = BluetoothDevices.paired()
        accessories = PowerSources.accessories()
        mac = PowerSources.macBattery()
        rebuild()
    }

    private func refreshProfiler() {
        BluetoothDevices.profiler { [weak self] entries in
            guard let self, !entries.isEmpty else { return }
            self.profiler = entries
            self.rebuild()
        }
    }

    private func refreshMobiles() {
        MobileDevices.fetch { [weak self] found in
            self?.mobiles = found
            self?.rebuild()
        }
    }

    private func handle(_ reading: HeadsetReading) {
        guard reading.rssi > -80 else { return }
        let previous = readings[reading.productID]
        if let previous, previous.date.timeIntervalSinceNow > -5, previous.rssi > reading.rssi + 10 {
            return // a stronger (closer) headset of the same model was seen just now
        }
        readings[reading.productID] = reading

        // Case opened (or headset appeared) near the Mac while not connected to it.
        let isNew = previous == nil || previous!.date.timeIntervalSinceNow < -20
        if isNew, settings.hudOnCaseOpen, reading.rssi > -60, launchDate.timeIntervalSinceNow < -10,
           (lastNearbyHUD[reading.productID]?.timeIntervalSinceNow ?? -.infinity) < -90 {
            rebuild()
            if let device = devices.first(where: { $0.address != nil && productID(of: $0) == reading.productID }),
               !device.isConnected {
                lastNearbyHUD[reading.productID] = Date()
                onHUD?(.nearby(device.id))
            }
        }

        if previous?.battery != reading.battery || lastRebuild.timeIntervalSinceNow < -2 { rebuild() }
    }

    private func productID(of device: Device) -> Int? {
        device.address.flatMap { profiler[$0]?.productID }
    }

    // MARK: Merge

    private func rebuild() {
        lastRebuild = Date()
        var list: [Device] = []
        var usedReadings = Set<Int>()
        var usedAccessories = Set<Int>()
        var usedMobiles = Set<String>()

        for p in paired.sorted(by: { $0.connected && !$1.connected }) {
            let entry = profiler[p.address]
            let model = entry?.productID.flatMap(HeadsetModels.lookup)
            var battery = entry?.battery ?? Battery()
            if !p.connected { battery = Battery() } // macOS only reports live levels for connected devices

            if let index = accessories.firstIndex(where: { $0.address == p.address }) {
                let a = accessories[index]
                usedAccessories.insert(index)
                battery = Battery(main: a.percent, mainCharging: a.charging)
            }
            if let pid = entry?.productID, let r = readings[pid], r.date.timeIntervalSinceNow > -60,
               !usedReadings.contains(pid) {
                usedReadings.insert(pid)
                battery = r.battery.filling(from: battery)
            }

            let kind = model != nil ? DeviceKind.headset : guessKind(name: p.name, classMajor: p.classMajor,
                                                                    minorType: entry?.minorType)
            if kind == .phone || kind == .tablet, let m = mobiles.first(where: { $0.name == p.name }) {
                usedMobiles.insert(m.udid)
                battery = m.battery
            }
            list.append(Device(id: "bt-\(p.address)", name: p.name, kind: kind,
                               symbol: symbol(for: kind, model: model),
                               battery: battery, isConnected: p.connected, address: p.address,
                               modelName: model?.name))
        }

        for (index, a) in accessories.enumerated() where !usedAccessories.contains(index) {
            let kind = guessKind(name: a.name, classMajor: 0, minorType: nil)
            list.append(Device(id: "hid-\(a.name)", name: a.name, kind: kind, symbol: symbol(for: kind, model: nil),
                               battery: Battery(main: a.percent, mainCharging: a.charging),
                               isConnected: true, address: nil, modelName: nil))
        }

        for m in mobiles where !usedMobiles.contains(m.udid) {
            let kind: DeviceKind = m.isTablet ? .tablet : .phone
            list.append(Device(id: "ios-\(m.udid)", name: m.name, kind: kind, symbol: symbol(for: kind, model: nil),
                               battery: m.battery, isConnected: true, address: nil, modelName: nil))
        }

        if let mac {
            list.append(Device(id: "mac", name: Host.current().localizedName ?? "This Mac", kind: .mac,
                               symbol: "laptopcomputer", battery: mac, isConnected: true, address: nil,
                               modelName: nil))
        }

        list.sort { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedCompare($1.name) == .orderedAscending }
        if list != devices { devices = list }
        checkEvents(list)
    }

    private func rank(_ d: Device) -> Int {
        if d.kind == .headset && d.isConnected { return 0 }
        if d.kind == .mac { return 2 }
        if d.isConnected { return 1 }
        if settings.pinnedIDs.contains(d.id) { return 3 }
        return 4
    }

    private func guessKind(name: String, classMajor: UInt32, minorType: String?) -> DeviceKind {
        let n = name.lowercased()
        if n.contains("mouse") { return .mouse }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("keyboard") { return .keyboard }
        if minorType == "Mouse" { return .mouse }
        if minorType == "Keyboard" { return .keyboard }
        if minorType == "Trackpad" { return .trackpad }
        if n.contains("iphone") || classMajor == 0x02 { return .phone }
        if n.contains("ipad") { return .tablet }
        if n.contains("watch") || classMajor == 0x07 { return .watch }
        if classMajor == 0x04 || minorType == "Headphones" || minorType == "Headset" || n.contains("airpods")
            || n.contains("beats") || n.contains("headphone") || n.contains("buds") { return .headset }
        return .other
    }

    private func symbol(for kind: DeviceKind, model: HeadsetModel?) -> String {
        switch kind {
        case .headset:
            let fallback = model?.singleBattery == true ? "headphones" : "airpods"
            return availableSymbol(model?.symbol ?? "headphones", fallback: availableSymbol(fallback, fallback: "headphones"))
        case .mouse: return availableSymbol("magicmouse", fallback: "computermouse")
        case .keyboard: return "keyboard"
        case .trackpad: return availableSymbol("trackpad", fallback: "hand.point.up.left")
        case .mac: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    // MARK: Alerts and HUD events

    private func checkEvents(_ list: [Device]) {
        let settled = launchDate.timeIntervalSinceNow < -6

        for d in list where d.kind == .headset {
            if d.isConnected && !connectedIDs.contains(d.id) {
                connectedIDs.insert(d.id)
                if settled && settings.hudOnConnect { onHUD?(.connected(d.id)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refreshProfiler() }
            } else if !d.isConnected {
                connectedIDs.remove(d.id)
            }
        }

        for d in list where !settings.mutedAlertIDs.contains(d.id) {
            if let low = d.battery.lowest {
                if low <= settings.lowThreshold && !d.battery.anyCharging && !lowAlerted.contains(d.id) {
                    lowAlerted.insert(d.id)
                    alert(.lowBattery(d.id, low), title: "\(d.name) battery is low", body: "\(low)% remaining.")
                } else if low > settings.lowThreshold + 5 || d.battery.anyCharging {
                    lowAlerted.remove(d.id)
                }
            }
            let chargingParts = d.battery.parts.filter(\.charging)
            if settings.notifyFullCharge, !chargingParts.isEmpty, chargingParts.allSatisfy({ $0.level >= 100 }) {
                if !fullAlerted.contains(d.id) {
                    fullAlerted.insert(d.id)
                    alert(.charged(d.id), title: "\(d.name) is charged", body: "Battery is at 100%.")
                }
            } else if chargingParts.isEmpty {
                fullAlerted.remove(d.id)
            }
        }
    }

    private func alert(_ event: HUDEvent, title: String, body: String) {
        if settings.alertStyle != .notification { onHUD?(event) }
        if settings.alertStyle != .hud {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                         content: content, trigger: nil))
        }
    }
}
