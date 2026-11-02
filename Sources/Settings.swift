import Foundation
import ServiceManagement

enum HUDPosition: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    case large, compact
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AlertStyle: String, CaseIterable, Identifiable {
    case hud, notification, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hud: return "HUD"
        case .notification: return "Notification"
        case .both: return "HUD and notification"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var hudPosition: HUDPosition { didSet { defaults.set(hudPosition.rawValue, forKey: "hudPosition") } }
    @Published var hudStyle: HUDStyle { didSet { defaults.set(hudStyle.rawValue, forKey: "hudStyle") } }
    @Published var hudOnCaseOpen: Bool { didSet { defaults.set(hudOnCaseOpen, forKey: "hudOnCaseOpen") } }
    @Published var hudOnConnect: Bool { didSet { defaults.set(hudOnConnect, forKey: "hudOnConnect") } }
    @Published var lowThreshold: Int { didSet { defaults.set(lowThreshold, forKey: "lowThreshold") } }
    @Published var notifyFullCharge: Bool { didSet { defaults.set(notifyFullCharge, forKey: "notifyFullCharge") } }
    @Published var alertStyle: AlertStyle { didSet { defaults.set(alertStyle.rawValue, forKey: "alertStyle") } }
    @Published var mutedAlertIDs: Set<String> { didSet { defaults.set(Array(mutedAlertIDs), forKey: "mutedAlertIDs") } }
    @Published var pinnedIDs: Set<String> { didSet { defaults.set(Array(pinnedIDs), forKey: "pinnedIDs") } }
    @Published var showWidget: Bool { didSet { defaults.set(showWidget, forKey: "showWidget") } }
    @Published var menuBarPercent: Bool { didSet { defaults.set(menuBarPercent, forKey: "menuBarPercent") } }
    @Published var inputLockEnabled: Bool { didSet { defaults.set(inputLockEnabled, forKey: "inputLockEnabled") } }
    @Published var inputLockUID: String { didSet { defaults.set(inputLockUID, forKey: "inputLockUID") } }

    private init() {
        defaults.register(defaults: [
            "hudOnCaseOpen": true,
            "hudOnConnect": true,
            "lowThreshold": 20,
            "notifyFullCharge": false,
            "showWidget": false,
            "menuBarPercent": true,
            "inputLockEnabled": false,
        ])
        hudPosition = HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .center
        hudStyle = HUDStyle(rawValue: defaults.string(forKey: "hudStyle") ?? "") ?? .large
        hudOnCaseOpen = defaults.bool(forKey: "hudOnCaseOpen")
        hudOnConnect = defaults.bool(forKey: "hudOnConnect")
        lowThreshold = defaults.integer(forKey: "lowThreshold")
        notifyFullCharge = defaults.bool(forKey: "notifyFullCharge")
        alertStyle = AlertStyle(rawValue: defaults.string(forKey: "alertStyle") ?? "") ?? .both
        mutedAlertIDs = Set(defaults.stringArray(forKey: "mutedAlertIDs") ?? [])
        pinnedIDs = Set(defaults.stringArray(forKey: "pinnedIDs") ?? [])
        showWidget = defaults.bool(forKey: "showWidget")
        menuBarPercent = defaults.bool(forKey: "menuBarPercent")
        inputLockEnabled = defaults.bool(forKey: "inputLockEnabled")
        inputLockUID = defaults.string(forKey: "inputLockUID") ?? ""
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }

    func togglePinned(_ id: String) {
        if pinnedIDs.contains(id) { pinnedIDs.remove(id) } else { pinnedIDs.insert(id) }
    }

    func toggleMuted(_ id: String) {
        if mutedAlertIDs.contains(id) { mutedAlertIDs.remove(id) } else { mutedAlertIDs.insert(id) }
    }
}
