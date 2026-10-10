import Foundation
import Network
import Security
import CoreAudio

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: " + message); exit(1) }
}
func spin(_ seconds: Double, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}

// Arbitrary TCP segmentation and coalescing, not one-packet-per-read assumptions.
let original = Wire.packet(1, Data("TA2:test-password-123456".utf8)) + Wire.packet(3, Data(repeating: 0, count: 4096)) + Wire.packet(4, Data(repeating: 1, count: 8))
for split in 0...original.count {
    var data = Data(original.prefix(split))
    var messages: [(UInt8, Data)] = []
    while let message = try Wire.take(&data) { messages.append(message) }
    data.append(original.dropFirst(split))
    while let message = try Wire.take(&data) { messages.append(message) }
    check(messages.map { $0.0 } == [1, 3, 4], "fragmented kinds at \(split)")
    check(messages[1].1.count == 4096 && data.isEmpty, "fragmented payload")
}
for bad in [Data([0,0,0,0]), Data([255,255,255,255]), Data([0,3,0,2])] {
    var data = bad; var rejected = false
    do { _ = try Wire.take(&data) } catch { rejected = true }
    check(rejected, "reject malformed length")
}
print("PASS: all TCP split points, coalesced packets, invalid lengths")

// Exercise the actual receiver and built-in audio graph using silence only.
let bridge = Bridge()
bridge.receiver = true; bridge.secret = "test-password-123456"; bridge.start()
check(bridge.running, "receiver started")
let client = NWConnection(host: "127.0.0.1", port: 49731, using: Transport.parameters(secret: "test-password-123456"))
var ready = false
client.stateUpdateHandler = { if case .ready = $0 { ready = true } }
client.start(queue: .main)
check(spin(4) { ready }, "loopback TCP connect")
let tls = client.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
check(tls != nil, "TLS metadata available")
if let tls {
    check(sec_protocol_metadata_get_negotiated_tls_protocol_version(tls.securityProtocolMetadata) == .TLSv12, "TLS 1.2 negotiated")
    check(sec_protocol_metadata_get_negotiated_tls_ciphersuite(tls.securityProtocolMetadata).rawValue == 0x00A8, "AES-128-GCM PSK negotiated")
}
client.send(content: Wire.packet(1, Data("TA2:test-password-123456".utf8)), completion: .contentProcessed { _ in })
var reply = Data()
client.receive(minimumIncompleteLength: 5, maximumLength: 1024) { data, _, _, _ in if let data { reply = data } }
check(spin(5) { !reply.isEmpty }, "receiver authentication reply")
let packet = try Wire.take(&reply)
check(packet?.0 == 2, "authenticated receiver and built-in output started")
client.send(content: Wire.packet(3, Data(repeating: 0, count: 3840)), completion: .contentProcessed { _ in })
var echo = Data()
client.send(content: Wire.packet(4, Data(repeating: 7, count: 8)), completion: .contentProcessed { _ in })
client.receive(minimumIncompleteLength: 13, maximumLength: 1024) { data, _, _, _ in if let data { echo = data } }
check(spin(2) { !echo.isEmpty }, "heartbeat response")
let pong = try Wire.take(&echo)
check(pong?.0 == 5 && pong?.1 == Data(repeating: 7, count: 8), "heartbeat payload")
check(bridge.receiverFrames > 0, "PCM reached receiver")
func selectMode(_ value: UInt8) {
    var modeReply = Data()
    client.send(content: Wire.packet(6, Data([value])), completion: .contentProcessed { _ in })
    client.receive(minimumIncompleteLength: 6, maximumLength: 1024) { data, _, _, _ in if let data { modeReply = data } }
    check(spin(2) { !modeReply.isEmpty }, "mode acknowledged")
    let packet = try? Wire.take(&modeReply)
    check(packet?.0 == 7 && packet?.1 == Data([value]), "correct mode acknowledgement")
}
selectMode(0)
check(!bridge.receiverRemoteEnabled, "local mode stops remote player")
let before = bridge.receiverFrames
client.send(content: Wire.packet(3, Data(repeating: 0, count: 3840)), completion: .contentProcessed { _ in })
selectMode(0) // TCP ordering ensures the preceding PCM has been processed.
check(bridge.receiverFrames == before, "late audio ignored in local mode")
selectMode(1)
check(bridge.receiverRemoteEnabled, "remote mode restarts engine")
client.send(content: Wire.packet(3, Data(repeating: 0, count: 3840)), completion: .contentProcessed { _ in })
selectMode(1)
check(bridge.receiverFrames > before, "audio resumes after switching back")
client.cancel()
check(spin(3) { bridge.status.contains("等待连接") }, "disconnect releases session")
let wrong = NWConnection(host: "127.0.0.1", port: 49731, using: Transport.parameters(secret: "test-password-123456"))
var wrongReady = false
wrong.stateUpdateHandler = { if case .ready = $0 { wrongReady = true } }
wrong.start(queue: .main)
check(spin(3) { wrongReady }, "second TCP connection")
wrong.send(content: Wire.packet(1, Data("TA2:wrong-password".utf8)), completion: .contentProcessed { _ in })
check(spin(3) { bridge.status.contains("口令不匹配") }, "wrong password rejected")
wrong.cancel()
check(spin(3) { bridge.status.contains("等待连接") }, "wrong app authentication cleaned up")
let badTLS = NWConnection(host: "127.0.0.1", port: 49731, using: Transport.parameters(secret: "different-TLS-secret"))
var badTLSReady = false
var badTLSFailed = false
badTLS.stateUpdateHandler = { state in
    if case .ready = state { badTLSReady = true }
    if case .failed = state { badTLSFailed = true }
    if case .waiting = state { badTLSFailed = true }
}
badTLS.start(queue: .main)
check(spin(6) { badTLSFailed }, "wrong TLS key rejected")
check(!badTLSReady, "wrong TLS key never reached ready")
badTLS.cancel()
_ = spin(2) { bridge.status.contains("等待连接") }
let plain = NWConnection(host: "127.0.0.1", port: 49731, using: .tcp)
var plainReady = false
plain.stateUpdateHandler = { if case .ready = $0 { plainReady = true } }
plain.start(queue: .main)
check(spin(3) { plainReady }, "plaintext TCP socket opened")
var plainClosed = false
var plainAuthenticated = false
plain.send(content: Wire.packet(1, Data("TA2:test-password-123456".utf8)), completion: .contentProcessed { _ in })
plain.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, done, error in
    plainClosed = done || error != nil
    if let data { var d = data; plainAuthenticated = (try? Wire.take(&d))?.0 == 2 }
}
_ = spin(3) { plainClosed || plainAuthenticated }
check(!plainAuthenticated, "no plaintext fallback")
plain.cancel(); bridge.stop()
check(!bridge.running && bridge.status == "已停止", "stop cleanup")
print("PASS: loopback receiver, authentication, silent PCM playback, heartbeat, disconnect, wrong password, negotiated TLS cipher, wrong PSK, no plaintext authentication, stop")

// Fake device backend: no changes to the host's system volume or mute state.
final class FakeMute: MuteBackend {
    var device: AudioDeviceID = 1
    var states: [AudioDeviceID: UInt32] = [1: 0, 2: 1]
    var failWrites = false
    func defaultDevice() throws -> AudioDeviceID { device }
    func read(_ id: AudioDeviceID) throws -> UInt32 { states[id]! }
    func write(_ id: AudioDeviceID, _ value: UInt32) throws {
        if failWrites { throw NSError(domain: "test unsupported device", code: 1) }
        states[id] = value
    }
}
let fake = FakeMute(); let local = LocalOutput(backend: fake)
try local.mute(); try local.mute()
check(fake.states[1] == 1, "local mute is idempotent")
try local.restore()
check(fake.states[1] == 0, "original mute restored")
fake.states[1] = 1
try local.mute(); try local.restore()
check(fake.states[1] == 1, "originally muted device stays muted")
fake.states[1] = 0
try local.mute(); fake.device = 2; try local.mute()
check(fake.states[1] == 0 && fake.states[2] == 1, "output change restores old device first")
try local.restore()
check(fake.states[2] == 1, "new device original state preserved")
fake.device = 1; fake.failWrites = true
var muteFailed = false
do { try local.mute() } catch { muteFailed = true }
check(muteFailed && fake.states[1] == 0, "unsupported mute reports failure")
fake.failWrites = false
try local.mute(); fake.states[1] = 0; try local.restore()
check(fake.states[1] == 0, "user unmute preserved on restore")
print("PASS: remote/local mode acknowledgement, queue flush, ignored late PCM, playback restart, reversible local mute and device change")
