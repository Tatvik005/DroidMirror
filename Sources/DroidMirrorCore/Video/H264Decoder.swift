import Foundation
import CoreMedia
import AVFoundation
import VideoToolbox

public final class H264Decoder {
    public private(set) var currentSPS: Data?
    public private(set) var currentPPS: Data?
    public private(set) var formatDescription: CMVideoFormatDescription?
    public private(set) var videoDimensions: (width: Int, height: Int) = (0, 0)

    public weak var displayLayer: AVSampleBufferDisplayLayer?

    public var onDimensionChange: ((Int, Int) -> Void)?
    public var onFPSUpdate: ((Int) -> Void)?

    private var frameCount: Int = 0
    private var lastFPSUpdateTime: TimeInterval = CACurrentMediaTime()
    private let fpsQueue = DispatchQueue(label: "com.droidmirror.fps")

    public init() {}

    /// Reset SPS/PPS and format description on mode switch or disconnection.
    public func reset() {
        currentSPS = nil
        currentPPS = nil
        formatDescription = nil
        videoDimensions = (0, 0)
        frameCount = 0
    }

    /// Update dimensions directly from scrcpy session metadata.
    public func updateDimensions(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if videoDimensions.width != width || videoDimensions.height != height {
            videoDimensions = (width, height)
            DispatchQueue.main.async { [weak self] in
                self?.onDimensionChange?(width, height)
            }
        }
    }

    /// Process an H.264 packet (Annex-B format) from the stream demuxer.
    public func decodeAndDisplay(packet: Data, ptsUs: Int64, isConfig: Bool, isKeyFrame: Bool) {
        let nals = NALParser.parseAnnexB(data: packet)
        guard !nals.isEmpty else { return }

        var newParameterSets = false
        var avccPayload = Data()

        for nal in nals {
            if nal.isSPS {
                currentSPS = nal.data
                newParameterSets = true
            } else if nal.isPPS {
                currentPPS = nal.data
                newParameterSets = true
            } else {
                // Video slice or SEI - append 4-byte big-endian length prefix + NAL data
                var lengthBE = UInt32(nal.data.count).bigEndian
                withUnsafeBytes(of: &lengthBE) { avccPayload.append(contentsOf: $0) }
                avccPayload.append(nal.data)
            }
        }

        if newParameterSets, let sps = currentSPS, let pps = currentPPS {
            createFormatDescription(sps: sps, pps: pps)
        }

        // If this was purely a configuration packet without slices, we are done
        guard !avccPayload.isEmpty, let formatDesc = formatDescription else {
            return
        }

        enqueueSampleBuffer(avccData: avccPayload, ptsUs: ptsUs, formatDescription: formatDesc)
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        var newFormatDesc: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                guard let spsBase = spsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return OSStatus(-1)
                }
                let parameterSets: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let parameterSetSizes: [Int] = [spsPtr.count, ppsPtr.count]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSets,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDesc
                )
            }
        }

        if status == noErr, let format = newFormatDesc {
            self.formatDescription = format
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            if width > 0 && height > 0 && (videoDimensions.width != width || videoDimensions.height != height) {
                videoDimensions = (width, height)
                DispatchQueue.main.async { [weak self] in
                    self?.onDimensionChange?(width, height)
                }
            }
        }
    }

    private func enqueueSampleBuffer(avccData: Data, ptsUs: Int64, formatDescription: CMVideoFormatDescription) {
        guard let displayLayer = displayLayer else { return }

        // 1. Create CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let memoryStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard memoryStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            return
        }

        let replaceStatus = avccData.withUnsafeBytes { rawPtr in
            guard let base = rawPtr.baseAddress else { return OSStatus(-1) }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }

        guard replaceStatus == kCMBlockBufferNoErr else { return }

        // 2. Timing Info
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(max(0, ptsUs)), timescale: 1_000_000),
            decodeTimeStamp: CMTime.invalid
        )

        // 3. Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccData.count

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sample = sampleBuffer else {
            return
        }

        // 4. Attach display immediately flag for zero-latency presentation
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        // 5. Enqueue to display layer on main thread
        DispatchQueue.main.async { [weak self, weak displayLayer] in
            guard let layer = displayLayer else { return }
            if layer.status == .failed {
                layer.flush()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sample)
                self?.trackFrameRendered()
            }
        }
    }

    private func trackFrameRendered() {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFPSUpdateTime
        if elapsed >= 1.0 {
            let calculatedFPS = Int(Double(frameCount) / elapsed)
            frameCount = 0
            lastFPSUpdateTime = now
            onFPSUpdate?(calculatedFPS)
        }
    }
}
