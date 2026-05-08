import AVFoundation
import XCTest

/// Creates a short video file with a silent audio track at `url` using AVAssetWriter.
/// Used by multiple test files to produce real video assets for testing.
func makeTestVideo(at url: URL, duration: Double = 1.0, testCase: XCTestCase) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 320,
        AVVideoHeightKey: 240
    ]
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false
    writer.add(videoInput)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240
        ]
    )

    let sampleRate = 44100.0
    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )
    var pcmFormatDesc: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &pcmFormatDesc
    )
    guard let pcmFormatDesc else {
        throw NSError(domain: "TestHelpers", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "CMAudioFormatDescriptionCreate failed"])
    }

    let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64000
    ]
    let audioInput = AVAssetWriterInput(mediaType: .audio,
                                        outputSettings: audioSettings,
                                        sourceFormatHint: pcmFormatDesc)
    audioInput.expectsMediaDataInRealTime = false
    writer.add(audioInput)

    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Write video frames
    var pixelBuffer: CVPixelBuffer?
    let cvStatus = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
    guard cvStatus == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "TestHelpers", code: Int(cvStatus),
                      userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed: \(cvStatus)"])
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
        memset(base, 0, CVPixelBufferGetDataSize(pixelBuffer))
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    let fps: Int32 = 30
    let totalFrames = Int(duration * Double(fps))
    for frame in 0..<totalFrames {
        while !videoInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
        let time = CMTime(value: CMTimeValue(frame), timescale: fps)
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }
    videoInput.markAsFinished()

    // Write silent audio samples (PCM → AAC-encoded in the file)
    let totalSamples = Int(duration * sampleRate)
    let chunkSize = 4096
    var samplesWritten = 0
    while samplesWritten < totalSamples {
        while !audioInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
        let count = min(chunkSize, totalSamples - samplesWritten)
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: count * 2,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: count * 2,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else { break }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: count * 2)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(samplesWritten), timescale: CMTimeScale(sampleRate)),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: pcmFormatDesc,
            sampleCount: count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        if let sampleBuffer { audioInput.append(sampleBuffer) }
        samplesWritten += count
    }
    audioInput.markAsFinished()

    let expectation = testCase.expectation(description: "AVAssetWriter finish")
    writer.finishWriting { expectation.fulfill() }
    testCase.wait(for: [expectation], timeout: 10)

    if writer.status == .failed {
        throw writer.error ?? NSError(domain: "TestHelpers", code: -2,
                                      userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed"])
    }
}
