import SwiftUI
import AppKit

@main
struct ThunderAudioApp: App {
    @StateObject private var bridge = Bridge()
    var body: some Scene {
        MenuBarExtra("ThunderAudio", systemImage: bridge.running ? "waveform.circle.fill" : "waveform.circle") {
            Panel(bridge: bridge).frame(width: 410).padding(16)
        }.menuBarExtraStyle(.window)
    }
}
struct Panel: View {
    @ObservedObject var bridge: Bridge
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("ThunderAudio 雷雳音频桥 0.4.1").font(.headline)
                Picker("本机角色", selection: $bridge.receiver) {
                    Text("接收端 · MacBook").tag(true)
                    Text("发送端 · Mac mini").tag(false)
                }.disabled(bridge.running)
                if !bridge.receiver {
                    Picker("声音播放位置", selection: $bridge.remotePlayback) {
                        Text("Mac mini").tag(false)
                        Text("MacBook").tag(true)
                    }.pickerStyle(.segmented)
                    Text(bridge.destinationStatus).font(.caption).foregroundStyle(.secondary)
                    Picker("接收设备", selection: $bridge.selectedPeerID) {
                        Text("请选择设备").tag("")
                        ForEach(bridge.peers) { peer in Text(peer.name).tag(peer.id) }
                        if !bridge.selectedPeerID.isEmpty, !bridge.peers.contains(where: { $0.id == bridge.selectedPeerID }), let saved = DiscoveredPeer.decode(bridge.selectedPeerID) {
                            Text(saved.name + "（上次连接，当前未发现）").tag(saved.id)
                        }
                    }.disabled(bridge.running)
                    HStack {
                        Text(bridge.discoveryStatus).font(.caption).foregroundStyle(.secondary)
                        Button("重新搜索") { bridge.refreshDiscovery() }
                    }
                    SecureField("首次连接输入接收端的配对码", text: $bridge.secret).disabled(bridge.running)
                } else {
                    TextField("接收端配对码：6 位数字或长口令", text: $bridge.secret).disabled(bridge.running)
                    HStack {
                        Button("生成新配对码") { bridge.secret = Pairing.newPIN() }.disabled(bridge.running)
                        Text("首次在发送端输入这个码即可").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("记住配对码（系统钥匙串）", isOn: $bridge.rememberSecret)
                Toggle("打开应用后自动连接 / 接收", isOn: $bridge.autoConnect)
                Text(bridge.pairingStatus).font(.caption).foregroundStyle(.secondary)
                if bridge.receiver {
                    HStack { Text("音量"); Slider(value: $bridge.volume, in: 0...1); Text("\(Int(bridge.volume * 100))%") }
                }
                DisclosureGroup("网络与配对选项") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("网络接口", selection: $bridge.interfaceName) {
                            Text("自动路由（可能使用 Wi-Fi）").tag("auto")
                            ForEach(bridge.interfaces, id: \.name) { i in Text(NetworkDetails.label(i)).tag(i.name) }
                        }.disabled(bridge.running)
                        if !bridge.receiver {
                            TextField("发现失败时填写接收端 IP（可留空）", text: $bridge.host).disabled(bridge.running)
                        }
                        Text("6 位码适合可信局域网；安全要求更高时可输入 16–128 字节长口令。").font(.caption).foregroundStyle(.secondary)
                        Button("忘记当前设备配对") { bridge.forgetCredential() }
                        Button("网络设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!) }
                    }.padding(.top, 8)
                }
                Toggle("运行时阻止空闲睡眠", isOn: $bridge.stayAwake)
                if bridge.receiver { Text(bridge.sleepStatus).font(.caption).foregroundStyle(.secondary) }
                Text("此选项不能阻止合盖睡眠。合盖运行需满足 macOS 外接显示器条件。").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(bridge.status).textSelection(.enabled)
                Text(bridge.route).font(.caption).textSelection(.enabled)
                Text(bridge.metrics).font(.caption).monospacedDigit()
                HStack {
                    Button(bridge.running ? "停止" : (bridge.receiver ? "开始接收" : "连接")) { if bridge.running { bridge.stop() } else { bridge.start() } }
                    Spacer()
                    Button("退出") { bridge.stop(); NSApplication.shared.terminate(nil) }
                }
            }
        // ScrollView has no intrinsic content height in a MenuBarExtra window.
        // Give the popover a real height while leaving room for the menu bar.
        }.frame(height: min(640, max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 100)))
    }
}
