import Foundation
import Network
import SwiftUI
import IOKit.pwr_mgt
import AppKit

final class Bridge: ObservableObject {
    @Published var remotePlayback = true { didSet { changeDestination() } }
    @Published var destinationStatus = ""
    @Published var sleepStatus = SleepStatus.description()
    @Published var receiverFrames = 0
    @Published var receiverRemoteEnabled = true
    @Published var receiver = true
    @Published var running = false
    @Published var status = "未启动"
    @Published var route = "尚未连接"
    @Published var metrics = "等待音频"
    @Published var peers: [NWBrowser.Result] = []
    @Published var interfaces: [NWInterface] = []
    @Published var interfaceName = "auto"
    @Published var host = ""
    @Published var secret = ""
    @Published var selected = -1
    @Published var volume: Double = 0.7 { didSet { playback.volume = Float(volume) } }
    @Published var stayAwake = false { didSet { updateAssertion() } }
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var monitor = NWPathMonitor()
    private let playback = Playback()
    private let localOutput = LocalOutput()
    private var remoteConfirmed = false
    private var captureReady = false
    private var observations: [NSObjectProtocol] = []
    private var capture: Capture?
    private var incoming = Data()
    private var authenticated = false
    private var attempt = UUID()
    private var target: NWEndpoint?
    private var timer: Timer?
    private var authTimer: Timer?
    private var inFlight = 0
    private var retryAt = Date.distantPast
    private var pingAt = Date.distantPast
    private var lastSeen = Date()
    private var rtt: Double = 0
    private var assertion: IOPMAssertionID = 0
    private var discarded = 0
    private var suggestedBridge = false

    init() {
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.running else { return }; self.disconnect("系统即将休眠，音频暂停")
        })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.running else { return }
            if self.receiver { self.stop(); self.start() } else { self.retryAt = Date() }
        })
        monitor.pathUpdateHandler = { [weak self] path in DispatchQueue.main.async { guard let self else { return }
            self.interfaces = path.availableInterfaces
            if !self.running && !self.suggestedBridge && self.interfaceName == "auto" {
                let candidates = path.availableInterfaces.filter { NetworkDetails.thunderboltNames().contains($0.name) }
                if candidates.count == 1 {
                    self.interfaceName = candidates[0].name
                    self.suggestedBridge = true
                }
            } } }
        monitor.start(queue: DispatchQueue(label: "network.interfaces"))
        playback.completed = { [weak self] frames, generation in
            DispatchQueue.main.async {
                guard let self, generation == self.playback.generation else { return }
                self.playback.pendingFrames = max(0, self.playback.pendingFrames - frames)
            }
        }
        browser = NWBrowser(for: .bonjour(type: "_thunderaudio._tcp", domain: nil), using: .tcp)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.peers = results.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }
        }
        browser?.start(queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    private func parameters() throws -> NWParameters {
        let p = Transport.parameters(secret: secret)
        p.includePeerToPeer = false
        if interfaceName != "auto" {
            guard let i = interfaces.first(where: { $0.name == interfaceName }) else { throw NSError(domain: "所选接口不可用，请检查雷雳网桥", code: 1) }
            p.requiredInterface = i
        }
        return p
    }
    func start() {
        guard !running else { return }
        guard secret.utf8.count >= 16, secret.utf8.count <= 128 else { status = "连接口令需要 16–128 个 UTF-8 字节"; return }
        do {
            let p = try parameters()
            if receiver {
                let l = try NWListener(using: p, on: 49731)
                l.service = NWListener.Service(name: Host.current().localizedName ?? "MacBook", type: "_thunderaudio._tcp")
                l.newConnectionHandler = { [weak self] c in
                    guard let self, self.running else { c.cancel(); return }
                    // One active sender; never replace a live session with an unsolicited connection.
                    guard self.connection == nil else { c.cancel(); return }
                    self.install(c)
                }
                l.stateUpdateHandler = { [weak self] state in
                    if case .failed(let error) = state { self?.stop(); self?.status = "监听失败：\(error.localizedDescription)" }
                }
                listener = l; l.start(queue: .main)
                status = "等待发送端（端口 49731）"
            } else {
                if !host.trimmingCharacters(in: .whitespaces).isEmpty {
                    target = .hostPort(host: NWEndpoint.Host(host.trimmingCharacters(in: .whitespaces)), port: 49731)
                } else {
                    guard peers.indices.contains(selected) else { status = "请选择接收端或填写 IP"; return }
                    target = peers[selected].endpoint
                }
                running = true
                connect()
            }
            running = true; updateAssertion()
        } catch { status = error.localizedDescription }
    }
    private func connect() {
        guard running, let target else { return }
        do { install(NWConnection(to: target, using: try parameters())) }
        catch { status = error.localizedDescription; retryAt = Date().addingTimeInterval(3) }
    }
    private func install(_ c: NWConnection) {
        attempt = UUID(); let id = attempt
        connection = c; receiverRemoteEnabled = true; authenticated = false; incoming.removeAll(); inFlight = 0
        status = "正在连接 / 验证口令"
        lastSeen = Date()
        authTimer?.invalidate()
        authTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self, self.attempt == id, !self.authenticated else { return }
            self.disconnect("连接或口令验证超时")
        }
        c.stateUpdateHandler = { [weak self] state in
            guard let self, self.attempt == id else { return }
            switch state {
            case .ready:
                self.updateRoute(c)
                if !self.receiver { self.send(1, Data(("TA2:" + self.secret).utf8)) }
                self.read(c, id)
            case .failed(let error): self.disconnect(error.localizedDescription)
            case .waiting(let error): self.disconnect("网络不可用：\(error.localizedDescription)")
            default: break
            }
        }
        c.pathUpdateHandler = { [weak self, weak c] _ in
            guard let self, self.attempt == id, let c else { return }; self.updateRoute(c)
        }
        c.start(queue: .main)
    }
    private func updateRoute(_ c: NWConnection) {
        let path = c.currentPath
        let local = path?.localEndpoint.map { String(describing: $0) } ?? "未知"
        let remote = path?.remoteEndpoint.map { String(describing: $0) } ?? String(describing: c.endpoint)
        let names = path?.availableInterfaces.map { $0.name }.joined(separator: ", ") ?? "未知"
        let binding = interfaceName == "auto" ? "自动路由；可用接口 \(names)" : "限定接口 \(interfaceName)"
        route = "\(binding)\n\(local) → \(remote)"

    }
    private func read(_ c: NWConnection, _ id: UUID) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self, self.attempt == id else { return }
            if let data {
                self.incoming.append(data)
                do {
                    while let (kind, body) = try Wire.take(&self.incoming) {
                        try self.handle(kind, body)
                        guard self.attempt == id else { return }
                    }
                } catch { self.disconnect(error.localizedDescription); return }
            }
            if done || error != nil { self.disconnect(error?.localizedDescription ?? "对端断开"); return }
            self.read(c, id)
        }
    }
    private func handle(_ kind: UInt8, _ body: Data) throws {
        lastSeen = Date()
        if !authenticated {
            if receiver && kind == 1 && body == Data(("TA2:" + secret).utf8) {
                try playback.start()
                authenticated = true; authTimer?.invalidate(); send(2)
                status = "已连接 · 内置扬声器"
            } else if !receiver && kind == 2 && body.isEmpty {
                authenticated = true; authTimer?.invalidate(); status = "已连接 · 正在请求系统音频"
                remoteConfirmed = false
                send(6, Data([remotePlayback ? 1 : 0]))
                beginCapture()
            } else { disconnect("口令不匹配或协议版本不兼容") }
            return
        }
        switch kind {
        case 3:
            guard receiver, body.count > 0, body.count % 8 == 0 else { disconnect("无效音频数据"); return }
            if receiverRemoteEnabled { receiverFrames += body.count / 8; playback.append(body) }
        case 6:
            guard receiver, body.count == 1, body[0] <= 1 else { disconnect("无效播放切换"); return }
            receiverRemoteEnabled = body[0] == 1
            playback.stop()
            if receiverRemoteEnabled { try playback.start() }
            status = receiverRemoteEnabled ? "已连接 · MacBook 播放" : "已连接 · Mac mini 播放（本机暂停）"
            send(7, body)
        case 7:
            guard !receiver, body.count == 1, body[0] <= 1 else { disconnect("无效播放切换确认"); return }
            // Ignore an obsolete acknowledgement if the user switched again.
            if (body[0] == 1) == remotePlayback {
                remoteConfirmed = remotePlayback
                applyDestination()
            }
        case 4: guard body.count == 8 else { disconnect("无效心跳"); return }; send(5, body)
        case 5:
            guard body.count == 8 else { disconnect("无效心跳"); return }
            let sent = body.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
            if sent.isFinite { rtt = max(0, (ProcessInfo.processInfo.systemUptime - sent) * 1000) }
        default: disconnect("未知协议消息")
        }
    }
    private func beginCapture() {
        let id = attempt; let source = Capture(); capture = source
        source.audio = { [weak self] data in DispatchQueue.main.async {
            guard let self, self.attempt == id, self.authenticated, self.remotePlayback, self.remoteConfirmed else { return }
            if self.inFlight > 192000 { self.discarded += 1; return }
            self.send(3, data)
        } }
        source.failed = { [weak self] error in DispatchQueue.main.async { if self?.attempt == id { self?.disconnect("采集停止：" + error) } } }
        Task { @MainActor in
            do {
                try await source.start()
                guard attempt == id, running else { await source.stop(); return }
                captureReady = true
                applyDestination()
                status = "已连接 · 48 kHz 立体声"
            } catch {
                guard attempt == id else { await source.stop(); return }
                stop(); status = "采集失败：\(error.localizedDescription)。请检查屏幕与系统音频录制权限后重新启动。"
            }
        }
    }
    private func send(_ kind: UInt8, _ body: Data = Data()) {
        guard let c = connection else { return }
        let packet = Wire.packet(kind, body); let id = attempt
        inFlight += packet.count
        c.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, self.attempt == id else { return }
            self.inFlight = max(0, self.inFlight - packet.count)
            if let error { self.disconnect(error.localizedDescription) }
        })
    }
    private func disconnect(_ reason: String) {
        attempt = UUID(); authTimer?.invalidate(); connection?.cancel(); connection = nil
        authenticated = false; remoteConfirmed = false; captureReady = false
        incoming.removeAll(); playback.stop()
        do { try localOutput.restore(); destinationStatus = "本机原静音状态已恢复" }
        catch { destinationStatus = "恢复本机静音状态失败，请检查声音设置：\(error.localizedDescription)" }
        let old = capture; capture = nil
        Task { await old?.stop() }
        route = "未连接"
        status = receiver ? "等待连接 · \(reason)" : "3 秒后重连 · \(reason)"
        retryAt = Date().addingTimeInterval(3)
    }
    func stop() {
        running = false; target = nil; listener?.cancel(); listener = nil
        disconnect("已停止"); status = "已停止"; metrics = "等待音频"; updateAssertion()
    }
    private func tick() {
        if receiver { sleepStatus = SleepStatus.description() }
        guard running else { return }
        if !receiver && captureReady && remoteConfirmed && remotePlayback { applyDestination() }
        if connection == nil, !receiver, Date() >= retryAt { connect() }
        if authenticated {
            if Date().timeIntervalSince(lastSeen) > 12 { disconnect("心跳超时（可能休眠或断线）"); return }
            if Date().timeIntervalSince(pingAt) >= 2 {
                var stamp = ProcessInfo.processInfo.systemUptime
                send(4, withUnsafeBytes(of: &stamp) { Data($0) }); pingAt = Date()
            }
            metrics = String(format: "网络往返 %.1f ms · 本机播放队列 %.0f ms · 丢弃 %d 块", rtt, Double(playback.pendingFrames)/48, playback.dropped + discarded)
        }
    }
    private func changeDestination() {
        guard !receiver else { return }
        remoteConfirmed = false
        do { try localOutput.restore() } catch { destinationStatus = error.localizedDescription }
        if authenticated { send(6, Data([remotePlayback ? 1 : 0])) }
        applyDestination()
    }
    private func applyDestination() {
        guard !receiver else { return }
        if remotePlayback && remoteConfirmed && captureReady {
            do { try localOutput.mute(); destinationStatus = "MacBook 播放 · Mac mini 已静音" }
            catch {
                // Keep the selection honest: don't stream with two audible outputs.
                remotePlayback = false
                destinationStatus = "自动静音失败，已退回 Mac mini：\(error.localizedDescription)"
            }
        } else if !remotePlayback {
            destinationStatus = "Mac mini 播放 · 保留本机原音量与静音状态"
        } else { destinationStatus = "等待 MacBook 与采集就绪，本机暂不静音" }
    }
    private func updateAssertion() {
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        if running && stayAwake {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "ThunderAudio 音频桥运行中" as CFString, &assertion)
        }
    }
}
