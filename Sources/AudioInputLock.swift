import CoreAudio
import Foundation

struct AudioInput: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Keeps the Mac's microphone on the input you choose, so connecting a headset
/// doesn't switch it to the headset mic.
final class AudioInputLock: ObservableObject {
    @Published private(set) var inputs: [AudioInput] = []
    private let settings = Settings.shared
    private let system = AudioObjectID(kAudioObjectSystemObject)

    init() {
        reload()
        listen(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.enforce() }
        listen(kAudioHardwarePropertyDevices) { [weak self] in self?.reload(); self?.enforce() }
    }

    func enforce() {
        guard settings.inputLockEnabled, !settings.inputLockUID.isEmpty,
              let preferred = inputs.first(where: { $0.uid == settings.inputLockUID }),
              defaultInput() != preferred.id else { return }
        var id = preferred.id
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private func reload() {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return }
        inputs = ids.compactMap { id in
            guard inputChannels(id) > 0,
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            return AudioInput(id: id, uid: uid, name: name)
        }
    }

    private func defaultInput() -> AudioDeviceID {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id)
        return id
    }

    private func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func listen(_ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) {
        var address = globalAddress(selector)
        AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { _, _ in handler() }
    }

    private func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
