import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreAudio

// Wire format: interleaved Float32 little endian, stereo, 48 kHz.
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    var stream: SCStream?
    var audio: ((Data) -> Void)?
    var failed: ((String) -> Void)?
    let queue = DispatchQueue(label: "audio.capture")
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw NSError(domain: "没有可采集的显示器", code: 1) }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = s
        try await s.startCapture()
    }
    func stop() async { try? await stream?.stopCapture(); stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failed?(error.localizedDescription) }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let desc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM,
              asbd.pointee.mSampleRate == 48000,
              asbd.pointee.mChannelsPerFrame == 2,
              asbd.pointee.mBitsPerChannel == 32,
              asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        var required = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &required, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: max(required, MemoryLayout<AudioBufferList>.size), alignment: 16)
        defer { memory.deallocate() }
        var block: CMBlockBuffer?
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: required, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let frames = sampleBuffer.numSamples
        guard frames > 0, frames <= 24000 else { return }
        var samples = [Float](repeating: 0, count: frames * 2)
        if buffers.count == 2 {
            guard let l = buffers[0].mData, let r = buffers[1].mData,
                  buffers[0].mDataByteSize >= frames * 4, buffers[1].mDataByteSize >= frames * 4 else { return }
            for i in 0..<frames { samples[i*2] = l.load(fromByteOffset: i*4, as: Float.self); samples[i*2+1] = r.load(fromByteOffset: i*4, as: Float.self) }
        } else if buffers.count == 1, let p = buffers[0].mData, buffers[0].mDataByteSize >= frames * 8 {
            samples.withUnsafeMutableBytes { $0.copyMemory(from: UnsafeRawBufferPointer(start: p, count: frames * 8)) }
        } else { return }
        audio?(samples.withUnsafeBytes { Data($0) })
    }
}

// Accessed exclusively on the transport queue. Bounded scheduling drops backlog
// instead of letting TCP congestion turn into seconds of delayed playback.
final class Playback {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var scheduledEnd: AVAudioFramePosition = 0
    private var renderedFrames: AVAudioFramePosition {
        guard let nodeTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: nodeTime), time.isSampleTimeValid else { return 0 }
        return max(0, time.sampleTime)
    }
    var pendingFrames: Int { Int(max(0, scheduledEnd - renderedFrames)) }
    var lowLatency = false
    var queueLimitFrames: Int { lowLatency ? 5760 : 9600 }
    var catchUps = 0 // TA4 wire compatibility; destructive queue chasing removed.
    var fallbacks = 0
    var generation = 0
    var dropped = 0
    var volume: Float = 0.7 { didSet { player.volume = volume } }
    init() { engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format) }
    func start() throws { try selectBuiltIn(); try engine.start(); player.volume = volume; player.play() }
    func stop() { generation += 1; player.stop(); engine.stop(); scheduledEnd = 0 }
    func append(_ input: Data) {
        let data = input
        guard data.count % 8 == 0, data.count > 0, data.count <= 192000 else { return }
        let frames = data.count / 8
        let pending = pendingFrames
        if lowLatency && pending + frames > queueLimitFrames {
            // Keep all queued samples and the incoming block. If this source or
            // network cannot sustain the smaller budget, prefer continuous sound.
            lowLatency = false
            fallbacks += 1
        }
        // A single capture block must remain intact, even if larger than the
        // nominal budget. Queue growth is still bounded by the wire block limit.
        if pending > 0 && pending + frames > max(queueLimitFrames, frames) {
            dropped += 1; return
        }
        let scheduledFrames = frames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(scheduledFrames)), let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(scheduledFrames)
        data.withUnsafeBytes { raw in
            for i in 0..<scheduledFrames {
                let l = raw.loadUnaligned(fromByteOffset: i*8, as: Float.self)
                let r = raw.loadUnaligned(fromByteOffset: i*8+4, as: Float.self)
                channels[0][i] = l.isFinite ? max(-1, min(1, l)) : 0
                channels[1][i] = r.isFinite ? max(-1, min(1, r)) : 0
            }
        }
        let start = max(scheduledEnd, renderedFrames)
        scheduledEnd = start + AVAudioFramePosition(scheduledFrames)
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: 48000), options: [], completionHandler: nil)
    }
    func selectBuiltIn() throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { throw NSError(domain: "无法枚举音频设备", code: 2) }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
        let result = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        guard result == noErr else { throw NSError(domain: "无法读取音频设备", code: 3) }
        for id in ids {
            var transport: UInt32 = 0; var n = UInt32(MemoryLayout<UInt32>.size)
            var prop = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &prop, 0, nil, &n, &transport) == noErr, transport == kAudioDeviceTransportTypeBuiltIn else { continue }
            prop.mSelector = kAudioDevicePropertyStreams; prop.mScope = kAudioDevicePropertyScopeOutput
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &prop, 0, nil, &bytes) == noErr, bytes > 0 else { continue }
            var device = id
            guard let unit = engine.outputNode.audioUnit else { continue }
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status == noErr { return }
        }
        throw NSError(domain: "未找到可用的内置扬声器，请检查音频设备", code: 4)
    }
}
