import CoreBluetooth

struct HeadsetReading {
    let productID: Int
    let battery: Battery
    let rssi: Int
    let date: Date
}

/// Listens for the Bluetooth LE status broadcasts that AirPods and Beats send
/// (Apple "proximity pairing" messages) and decodes their battery levels.
final class AirPodsScanner: NSObject, CBCentralManagerDelegate {
    var onReading: ((HeadsetReading) -> Void)?
    private var central: CBCentralManager?

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let reading = Self.parse(data, rssi: RSSI.intValue) else { return }
        onReading?(reading)
    }

    /// Layout after the 2-byte company ID (0x004C):
    /// [0] 0x07 type, [1] length, [2] prefix, [3-4] product ID (little endian),
    /// [5] status, [6] pod levels (one nibble each), [7] charging flags | case level.
    static func parse(_ data: Data, rssi: Int) -> HeadsetReading? {
        let b = [UInt8](data)
        guard b.count >= 10, b[0] == 0x4C, b[1] == 0x00, b[2] == 0x07, b[3] >= 0x09 else { return nil }
        let productID = Int(b[6]) << 8 | Int(b[5])
        guard b[6] == 0x20 else { return nil }

        let flipped = (b[7] & 0x20) == 0
        let high = Int(b[8] >> 4), low = Int(b[8] & 0x0F)
        let caseNibble = Int(b[9] & 0x0F)
        let charge = Int(b[9] >> 4)

        var battery = Battery()
        let left = level(flipped ? high : low)
        let right = level(flipped ? low : high)
        let leftCharging = charge & (flipped ? 0b10 : 0b01) != 0
        let rightCharging = charge & (flipped ? 0b01 : 0b10) != 0

        if HeadsetModels.lookup(productID)?.singleBattery == true {
            battery.main = left ?? right
            battery.mainCharging = leftCharging || rightCharging
        } else {
            battery.left = left
            battery.right = right
            battery.leftCharging = left != nil && leftCharging
            battery.rightCharging = right != nil && rightCharging
            battery.caseLevel = level(caseNibble)
            battery.caseCharging = battery.caseLevel != nil && charge & 0b100 != 0
        }
        guard !battery.isEmpty else { return nil }
        return HeadsetReading(productID: productID, battery: battery, rssi: rssi, date: Date())
    }

    /// 0-10 means 0-100 %, 15 means "not available".
    private static func level(_ nibble: Int) -> Int? {
        nibble <= 10 ? min(nibble * 10, 100) : nil
    }
}
