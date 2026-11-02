import Foundation
import IOBluetooth
import IOKit
import IOKit.ps

struct PairedDevice {
    let address: String
    let name: String
    let connected: Bool
    let classMajor: UInt32
}

struct ProfilerEntry {
    let productID: Int?
    let battery: Battery
    let minorType: String?
}

struct AccessoryBattery {
    let address: String?
    let name: String
    let percent: Int
    let charging: Bool
}

enum BluetoothDevices {
    static func paired() -> [PairedDevice] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.compactMap { device in
            guard let address = device.addressString else { return nil }
            return PairedDevice(address: normalizeAddress(address),
                                name: device.nameOrAddress ?? address,
                                connected: device.isConnected(),
                                classMajor: device.deviceClassMajor)
        }
    }

    static func setConnected(_ connect: Bool, address: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            if let device = IOBluetoothDevice(addressString: address) {
                ok = (connect ? device.openConnection() : device.closeConnection()) == kIOReturnSuccess
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Battery levels and product IDs that macOS reports for paired devices.
    static func profiler(completion: @escaping ([String: ProfilerEntry]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var result: [String: ProfilerEntry] = [:]
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                result = parseProfiler(data)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func parseProfiler(_ data: Data) -> [String: ProfilerEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var out: [String: ProfilerEntry] = [:]
        for controller in controllers {
            for key in ["device_connected", "device_not_connected"] {
                for entry in controller[key] as? [[String: Any]] ?? [] {
                    for (_, value) in entry {
                        guard let info = value as? [String: Any],
                              let address = info["device_address"] as? String else { continue }
                        var battery = Battery()
                        battery.main = percent(info["device_batteryLevelMain"])
                        battery.left = percent(info["device_batteryLevelLeft"])
                        battery.right = percent(info["device_batteryLevelRight"])
                        battery.caseLevel = percent(info["device_batteryLevelCase"])
                        let productID = (info["device_productID"] as? String).flatMap {
                            Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16)
                        }
                        out[normalizeAddress(address)] = ProfilerEntry(productID: productID, battery: battery,
                                                                       minorType: info["device_minorType"] as? String)
                    }
                }
            }
        }
        return out
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }
}

enum PowerSources {
    /// Magic Mouse, Keyboard, Trackpad and other HID accessories that report a battery.
    static func accessories() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [AccessoryBattery] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let percent = dict["BatteryPercent"] as? Int else { continue }
            out.append(AccessoryBattery(address: (dict["DeviceAddress"] as? String).map(normalizeAddress),
                                        name: dict["Product"] as? String ?? "Accessory",
                                        percent: percent,
                                        charging: (dict["BatteryStatusFlags"] as? Int) == 3))
        }
        return out
    }

    /// This Mac's internal battery, or nil on desktop Macs.
    static func macBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            var battery = Battery()
            battery.main = current * 100 / max
            battery.mainCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            return battery
        }
        return nil
    }
}
