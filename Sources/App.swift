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
        VStack(alignment: .leading, spacing: 12) {
            Text("ThunderAudio 雷雳音频桥 0.2").font(.headline)
            Picker("本机角色", selection: $bridge.receiver) {
                Text("接收端 · MacBook").tag(true)
                Text("发送端 · Mac mini").tag(false)
            }.disabled(bridge.running)
            Picker("网络接口", selection: $bridge.interfaceName) {
                Text("自动路由（可能使用 Wi-Fi）").tag("auto")
                ForEach(bridge.interfaces, id: \.name) { i in Text(NetworkDetails.label(i)).tag(i.name) }
            }.disabled(bridge.running)
            if !bridge.receiver {
                Picker("声音播放位置", selection: $bridge.remotePlayback) {
                    Text("Mac mini").tag(false)
                    Text("MacBook").tag(true)
                }.pickerStyle(.segmented)
                Text(bridge.destinationStatus).font(.caption).foregroundStyle(.secondary)
                Picker("发现的接收端", selection: $bridge.selected) {
                    Text("请选择").tag(-1)
                    ForEach(Array(bridge.peers.enumerated()), id: \.offset) { index, peer in
                        Text(String(describing: peer.endpoint)).tag(index)
                    }
                }.disabled(bridge.running)
                TextField("或填写接收端网桥 IP（端口固定 49731）", text: $bridge.host).disabled(bridge.running)
            }
            SecureField("两端输入同一连接口令（至少 16 字节）", text: $bridge.secret).disabled(bridge.running)
            Button("生成随机口令（复制给另一台 Mac）") {
                bridge.secret = UUID().uuidString + UUID().uuidString
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bridge.secret, forType: .string)
            }.disabled(bridge.running)
            if bridge.receiver {
                HStack { Text("音量"); Slider(value: $bridge.volume, in: 0...1); Text("\(Int(bridge.volume * 100))%") }
            }
            if bridge.receiver { Text(bridge.sleepStatus).font(.caption).foregroundStyle(.secondary) }
            Toggle("运行时阻止空闲睡眠", isOn: $bridge.stayAwake)
            Text("此选项不能阻止合盖睡眠。合盖运行需要满足 macOS 外接显示器模式条件。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(bridge.status).textSelection(.enabled)
            Text(bridge.route).font(.caption).textSelection(.enabled)
            Text(bridge.metrics).font(.caption).monospacedDigit()
            HStack {
                Button(bridge.running ? "停止" : "启动") { if bridge.running { bridge.stop() } else { bridge.start() } }
                Button("网络设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!) }
                Spacer()
                Button("退出") { bridge.stop(); NSApplication.shared.terminate(nil) }
            }
        }
    }
}
