import CoreAudio
import Foundation

/// Core Audio device introspection used to detect low-quality Bluetooth inputs.
///
/// AirPods (and most Bluetooth headsets) switch from the high-quality A2DP output
/// profile to the narrowband HFP/SCO "hands-free" profile the moment any app opens
/// their microphone. In that mode both the mic input and the audio output collapse
/// to telephone bandwidth (~8 kHz). Crucially, macOS's audio engine still *reports*
/// the input at 48 kHz (it upsamples the SCO stream at the HAL layer), so the only
/// reliable way to detect the condition is the device's transport type — not its
/// sample rate. Gist uses this to avoid recording through a Bluetooth mic.
enum AudioDeviceUtils {

    struct DeviceInfo {
        let id: AudioDeviceID
        let name: String
        let transport: String

        var isBluetooth: Bool { transport == "Bluetooth" }
    }

    // MARK: - Default devices

    static func defaultInput() -> DeviceInfo? {
        guard let id = defaultDeviceID(input: true) else { return nil }
        return info(for: id)
    }

    static func defaultOutput() -> DeviceInfo? {
        guard let id = defaultDeviceID(input: false) else { return nil }
        return info(for: id)
    }

    /// The built-in microphone, if present. Used as the high-quality fallback when
    /// the default input is a Bluetooth device in call mode.
    static func builtInInput() -> DeviceInfo? {
        for id in allDeviceIDs() where hasInputStreams(id) {
            if rawTransport(id) == kAudioDeviceTransportTypeBuiltIn {
                return info(for: id)
            }
        }
        return nil
    }

    // MARK: - Per-device queries

    static func info(for id: AudioDeviceID) -> DeviceInfo? {
        guard let name = name(for: id) else { return nil }
        return DeviceInfo(id: id, name: name, transport: transportLabel(rawTransport(id)))
    }

    static func name(for id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        let result = name as String
        return result.isEmpty ? nil : result
    }

    /// True if the device exposes at least one input channel.
    static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in abl where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    // MARK: - Transport

    static func transportLabel(_ raw: UInt32?) -> String {
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default: return "Unknown"
        }
    }

    private static func rawTransport(_ id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return nil
        }
        return transport
    }

    // MARK: - Enumeration

    private static func defaultDeviceID(input: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }
}
