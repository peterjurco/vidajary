import AVFoundation
import XCTest

/// Creates a short silent video file at `url` using AVAssetWriter.
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

    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240
        ]
    )

    // Create and zero the pixel buffer to avoid undefined content
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "TestHelpers", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed with status \(status)"])
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

    let expectation = testCase.expectation(description: "AVAssetWriter finish")
    writer.finishWriting { expectation.fulfill() }
    testCase.wait(for: [expectation], timeout: 10)
}
