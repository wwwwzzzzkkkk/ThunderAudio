# 验证记录

日期：2026-10-10（Asia/Singapore）。这是可构建的开发原型，不是完成双机硬件认证的发布版本。

## 已完成

- Command Line Tools：Swift 6.4，Swift 5 语言模式，arm64 / macOS 13 deployment target，优化构建成功。
- 完整 Xcode 27.1（27A9275）：项目 Release 构建成功；最新源码再次增量构建成功。Xcode 安装在 Downloads，通过进程内 DEVELOPER_DIR 选择，没有修改系统默认开发工具路径。构建使用 `CODE_SIGNING_ALLOWED=NO` 验证项目，分发 ZIP 则由独立构建脚本临时签名。
- Xcode project 和 Info.plist 的属性列表语法验证成功。
- TCP 帧协议：对完整组合数据的每个切分点测试；粘包恢复成功；拒绝零长度、超大长度等非法头。
- 实际本机回环网络：运行接收端状态机与 AVAudioEngine，正确口令建立连接；发送静音 PCM；心跳往返成功；断线释放会话；应用层错误口令被拒绝；停止清理成功。
- TLS 元数据：实际协商 TLS 1.2、0x00A8（PSK AES-128-GCM-SHA256）；不同 PSK 无法到达 ready 状态。明文客户端未获得应用验证成功响应。
- 上述测试先以 Command Line Tools、再通过新安装的 Xcode 工具链运行，最终均通过。
- 分发 ZIP 解压至独立临时目录后，`codesign --verify --deep --strict` 成功。
- 已打包应用启动冒烟检查：启动后保持运行三秒，未立即崩溃；随后终止测试进程。直接启动包内可执行文件时，系统日志出现一条 `sandbox_extension_issue_file_to_process` 警告，但进程保持运行；这不能证明权限交互已验证。没有进行菜单界面截图或人工视觉验收。

## 尚未验证

- Mac mini M5 Pro → MacBook Pro M1 Pro 的真实双机传输及内置扬声器实际声音。
- 真实 Thunderbolt Bridge 设备发现、IP 配置、指定接口路由、拔插恢复。
- 发送端系统录制权限交互、ScreenCaptureKit 的真实系统声音内容。测试没有主动录制用户音频。
- 音频端到端时延、影音同步、不同 macOS 版本、长时间播放及采样时钟漂移。
- 合盖播放、休眠唤醒、输出设备重配置。
- Developer ID 正式签名、公证、另一台 Mac 的 Gatekeeper / 权限表现。

## 复现

在工程目录运行 `./build.sh` 和 `./test.sh`。完整 Xcode 构建可运行 README 中的命令；若 Xcode 不在 Applications，先对当前命令设置 `DEVELOPER_DIR` 为实际 Xcode.app 内的 `Contents/Developer`。

开发原型保留明确边界：不注册远端硬件音频设备，不绕过系统合盖睡眠保护，不将 RTT 显示为端到端延迟，不宣称已完成双机测试。


## v0.2 更新验证

- Xcode 27.1 Release 增量构建通过。
- 新增真实 TLS 回环测试：Mac mini 模式确认、接收端队列停止、忽略晚到 PCM、切回 MacBook 后音频重新入队，均通过。
- 新增注入假设备的静音测试：重复静音、恢复原状态、保留原本静音、默认输出设备切换、不可写设备错误、尊重用户取消静音，均通过。测试不修改本机系统音量或静音状态。
- 用户反馈：v0.1 断开屏幕共享后，MacBook 已能播放声音。此反馈不代替 v0.2 的双机验收。
- 新版真实双机播放切换、系统静音时 ScreenCaptureKit 的采集表现、合盖及睡眠唤醒恢复尚未硬件验证。仅雷电线和电源不保证合盖运行。
