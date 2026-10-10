import Foundation
import CoreGraphics
import IOKit.ps

enum SleepStatus {
    static func description() -> String {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let code = displays.withUnsafeMutableBufferPointer { CGGetOnlineDisplayList(count, $0.baseAddress, &count) }
        let external = code == .success ? displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count : 0
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let powered = source == (kIOPSACPowerValue as String)
        if external == 0 { return "\(powered ? "已接交流电源" : "未检测到交流电源")，未检测到外接显示器：仅接雷电线不能保证合盖播放。请开盖使用，可让屏幕熄灭。" }
        if !powered { return "检测到外接显示器，但未检测到交流电源。合盖运行还需接电并连接键盘、鼠标。" }
        return "已检测到外接显示器与交流电源。还需外接键盘、鼠标并实测合盖；应用不能保证系统不休眠。"
    }
}
