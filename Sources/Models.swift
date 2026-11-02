import AppKit

struct Battery: Equatable {
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var mainCharging = false
    var leftCharging = false
    var rightCharging = false
    var caseCharging = false

    var isEmpty: Bool { main == nil && left == nil && right == nil && caseLevel == nil }

    /// Lowest level of the parts you wear or hold (the case is left out).
    var lowest: Int? { [main, left, right].compactMap { $0 }.min() }

    var anyCharging: Bool { mainCharging || leftCharging || rightCharging || caseCharging }

    var parts: [BatteryPart] {
        var out: [BatteryPart] = []
        if let main { out.append(BatteryPart(id: "main", label: "", level: main, charging: mainCharging)) }
        if let left { out.append(BatteryPart(id: "left", label: "L", level: left, charging: leftCharging)) }
        if let right { out.append(BatteryPart(id: "right", label: "R", level: right, charging: rightCharging)) }
        if let caseLevel { out.append(BatteryPart(id: "case", label: "Case", level: caseLevel, charging: caseCharging)) }
        return out
    }

    /// Fills parts missing from `self` with values from `other`.
    func filling(from other: Battery) -> Battery {
        var b = self
        if b.main == nil { b.main = other.main; b.mainCharging = other.mainCharging }
        if b.left == nil { b.left = other.left; b.leftCharging = other.leftCharging }
        if b.right == nil { b.right = other.right; b.rightCharging = other.rightCharging }
        if b.caseLevel == nil { b.caseLevel = other.caseLevel; b.caseCharging = other.caseCharging }
        return b
    }
}

struct BatteryPart: Identifiable {
    let id: String
    let label: String
    let level: Int
    let charging: Bool
}

enum DeviceKind {
    case headset, mouse, keyboard, trackpad, mac, phone, tablet, watch, other
}

struct Device: Identifiable, Equatable {
    let id: String
    var name: String
    var kind: DeviceKind
    var symbol: String
    var battery: Battery
    var isConnected: Bool
    /// Paired over Bluetooth, so it can be connected and disconnected.
    var address: String?
    var modelName: String?

    /// iPhone, iPad and Apple Watch are paired with the Mac for Continuity
    /// (Handoff, Auto Unlock) but can't be connected to it like a headset.
    var canConnect: Bool { address != nil && ![.phone, .tablet, .watch].contains(kind) }

    var statusText: String {
        if kind == .mac { return battery.mainCharging ? "This Mac · Charging" : "This Mac" }
        if address == nil { return "Connected" }
        if !canConnect { return "Paired for Continuity" }
        return isConnected ? "Connected" : "Not connected"
    }
}

struct HeadsetModel {
    let name: String
    let symbol: String
    let singleBattery: Bool
}

enum HeadsetModels {
    /// Bluetooth product IDs of Apple and Beats headsets.
    static let table: [Int: HeadsetModel] = [
        0x2002: HeadsetModel(name: "AirPods", symbol: "airpods", singleBattery: false),
        0x200F: HeadsetModel(name: "AirPods (2nd gen)", symbol: "airpods", singleBattery: false),
        0x2013: HeadsetModel(name: "AirPods (3rd gen)", symbol: "airpods.gen3", singleBattery: false),
        0x2019: HeadsetModel(name: "AirPods 4", symbol: "airpods.gen4", singleBattery: false),
        0x201B: HeadsetModel(name: "AirPods 4 (ANC)", symbol: "airpods.gen4", singleBattery: false),
        0x200E: HeadsetModel(name: "AirPods Pro", symbol: "airpodspro", singleBattery: false),
        0x2014: HeadsetModel(name: "AirPods Pro 2", symbol: "airpodspro", singleBattery: false),
        0x2024: HeadsetModel(name: "AirPods Pro 2 (USB-C)", symbol: "airpodspro", singleBattery: false),
        0x200A: HeadsetModel(name: "AirPods Max", symbol: "airpodsmax", singleBattery: true),
        0x201F: HeadsetModel(name: "AirPods Max (USB-C)", symbol: "airpodsmax", singleBattery: true),
        0x2003: HeadsetModel(name: "Powerbeats3", symbol: "beats.powerbeats3", singleBattery: true),
        0x2005: HeadsetModel(name: "BeatsX", symbol: "beats.earphones", singleBattery: true),
        0x2006: HeadsetModel(name: "Beats Solo3", symbol: "beats.headphones", singleBattery: true),
        0x2009: HeadsetModel(name: "Beats Studio3", symbol: "beats.headphones", singleBattery: true),
        0x200B: HeadsetModel(name: "Powerbeats Pro", symbol: "beats.powerbeatspro", singleBattery: false),
        0x200C: HeadsetModel(name: "Beats Solo Pro", symbol: "beats.headphones", singleBattery: true),
        0x200D: HeadsetModel(name: "Powerbeats", symbol: "beats.powerbeats", singleBattery: true),
        0x2010: HeadsetModel(name: "Beats Flex", symbol: "beats.earphones", singleBattery: true),
        0x2011: HeadsetModel(name: "Beats Studio Buds", symbol: "beats.studiobuds", singleBattery: false),
        0x2012: HeadsetModel(name: "Beats Fit Pro", symbol: "beats.fitpro", singleBattery: false),
        0x2016: HeadsetModel(name: "Beats Studio Buds+", symbol: "beats.studiobuds", singleBattery: false),
        0x2017: HeadsetModel(name: "Beats Studio Pro", symbol: "beats.headphones", singleBattery: true),
    ]

    static func lookup(_ productID: Int) -> HeadsetModel? { table[productID] }
}

/// Returns `name` if this macOS has that SF Symbol, otherwise `fallback`.
func availableSymbol(_ name: String, fallback: String) -> String {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
}

func normalizeAddress(_ address: String) -> String {
    address.lowercased().replacingOccurrences(of: ":", with: "-")
}
