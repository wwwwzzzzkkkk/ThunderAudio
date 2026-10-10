import Foundation
import CoreAudio

protocol MuteBackend {
    func defaultDevice() throws -> AudioDeviceID
    func read(_ id: AudioDeviceID) throws -> UInt32
    func write(_ id: AudioDeviceID, _ value: UInt32) throws
}
struct HardwareMute: MuteBackend {
    func defaultDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { throw failure() }
        return id
    }
    func read(_ id: AudioDeviceID) throws -> UInt32 {
        var address = property(); var value: UInt32 = 0; var size: UInt32 = 4
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { throw failure() }
        return value
    }
    func write(_ id: AudioDeviceID, _ value: UInt32) throws {
        var address = property(); var mutable = value; var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue,
              AudioObjectSetPropertyData(id, &address, 0, nil, 4, &mutable) == noErr,
              try read(id) == value else { throw failure() }
    }
    private func property() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private func failure() -> NSError { NSError(domain: "当前 Mac mini 输出设备不支持自动静音，请在声音设置中手动调整", code: 1) }
}
// No volume changes. Restore only the device we changed, and only if it still
// has our mute value. Failed restores retain the snapshot for a later retry.
final class LocalOutput {
    private let backend: MuteBackend
    private var saved: (AudioDeviceID, UInt32)?
    init(backend: MuteBackend = HardwareMute()) { self.backend = backend }
    func mute() throws {
        let id = try backend.defaultDevice()
        if let saved, saved.0 != id { try restore() }
        if saved == nil { saved = (id, try backend.read(id)) }
        if try backend.read(id) == 1 { return }
        do { try backend.write(id, 1) }
        catch { try? restore(); throw error }
    }
    func restore() throws {
        guard let snapshot = saved else { return }
        if try backend.read(snapshot.0) == 1 { try backend.write(snapshot.0, snapshot.1) }
        saved = nil
    }
}
