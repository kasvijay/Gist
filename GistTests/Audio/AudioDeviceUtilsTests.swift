import XCTest
import CoreAudio
@testable import Gist

/// Guards the Core Audio device introspection that drives Bluetooth detection.
/// A bug here previously crashed recording, so these tests assert the queries are
/// total (never crash) and internally consistent, without assuming any specific
/// hardware is present (CI runners may have no audio devices).
final class AudioDeviceUtilsTests: XCTestCase {

    func testTransportLabelMapsKnownTypes() {
        XCTAssertEqual(AudioDeviceUtils.transportLabel(kAudioDeviceTransportTypeBuiltIn), "Built-in")
        XCTAssertEqual(AudioDeviceUtils.transportLabel(kAudioDeviceTransportTypeBluetooth), "Bluetooth")
        XCTAssertEqual(AudioDeviceUtils.transportLabel(kAudioDeviceTransportTypeBluetoothLE), "Bluetooth")
        XCTAssertEqual(AudioDeviceUtils.transportLabel(kAudioDeviceTransportTypeUSB), "USB")
    }

    func testTransportLabelHandlesNilAndUnknown() {
        XCTAssertEqual(AudioDeviceUtils.transportLabel(nil), "Unknown")
        XCTAssertEqual(AudioDeviceUtils.transportLabel(0xDEAD_BEEF), "Unknown")
    }

    func testDefaultInputQueryDoesNotCrashAndIsConsistent() {
        // May be nil on a machine with no input device — that's acceptable.
        if let info = AudioDeviceUtils.defaultInput() {
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertEqual(info.isBluetooth, info.transport == "Bluetooth")
        }
    }

    func testDefaultOutputQueryDoesNotCrash() {
        _ = AudioDeviceUtils.defaultOutput()
    }

    func testBuiltInInputQueryDoesNotCrash() {
        // On most Macs this is the built-in mic; in CI it may be nil. Either is fine —
        // we only require that enumerating every device + reading its stream config
        // and transport never crashes.
        if let builtIn = AudioDeviceUtils.builtInInput() {
            XCTAssertEqual(builtIn.transport, "Built-in")
            XCTAssertFalse(builtIn.name.isEmpty)
        }
    }

    func testInfoForInvalidDeviceIDReturnsNil() {
        // A bogus device id must not crash; it should simply yield nil.
        XCTAssertNil(AudioDeviceUtils.info(for: AudioDeviceID(0xFFFF_FFFF)))
    }
}
