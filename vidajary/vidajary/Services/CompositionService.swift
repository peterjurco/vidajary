import AVFoundation

struct CompositionResult {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
}

enum CompositionService {

    static func buildComposition(from clipURLs: [URL]) async throws -> CompositionResult {
        let composition = AVMutableComposition()
        guard !clipURLs.isEmpty else { return CompositionResult(composition: composition, videoComposition: nil) }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return CompositionResult(composition: composition, videoComposition: nil) }

        var audioTrack: AVMutableCompositionTrack? = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var audioInserted = false
        var cursor = CMTime.zero
        var renderSize: CGSize? = nil
        var frameRate: Float = 30
        var clipInfos: [(timeRange: CMTimeRange, naturalSize: CGSize, preferredTransform: CGAffineTransform)] = []

        for url in clipURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isValid, duration.seconds > 0 else { continue }
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let srcVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: srcVideo, at: cursor)
                let naturalSize = try await srcVideo.load(.naturalSize)
                let preferredTransform = try await srcVideo.load(.preferredTransform)
                if renderSize == nil {
                    renderSize = orientedSize(naturalSize: naturalSize, transform: preferredTransform)
                    frameRate = try await srcVideo.load(.nominalFrameRate)
                }
                clipInfos.append((
                    timeRange: CMTimeRange(start: cursor, duration: duration),
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform
                ))
            }
            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                audioInserted = true
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        if !audioInserted, let audioTrack {
            composition.removeTrack(audioTrack)
        }

        guard let renderSize, !clipInfos.isEmpty else {
            return CompositionResult(composition: composition, videoComposition: nil)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let safeFrameRate = max(1, Int32(frameRate.rounded()))
        videoComposition.frameDuration = CMTime(value: 1, timescale: safeFrameRate)

        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: cursor)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        for info in clipInfos {
            let t = fitTransform(
                naturalSize: info.naturalSize,
                preferredTransform: info.preferredTransform,
                renderSize: renderSize
            )
            layerInstruction.setTransform(t, at: info.timeRange.start)
        }

        mainInstruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [mainInstruction]

        return CompositionResult(composition: composition, videoComposition: videoComposition)
    }

    static func buildComposition(from clips: [Clip], in directory: URL) async throws -> CompositionResult {
        let urls = clips
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { directory.appendingPathComponent($0.filename) }
        return try await buildComposition(from: urls)
    }

    // Returns the display dimensions after applying preferredTransform.
    private static func orientedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let isRotated = abs(transform.b) > 0.5
        return isRotated
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize
    }

    // Builds the transform for a layer instruction that maps the clip into renderSize,
    // respecting rotation and scaling to fit (letterbox if aspect ratios differ).
    private static func fitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let oriented = orientedSize(naturalSize: naturalSize, transform: preferredTransform)
        let scaleX = renderSize.width / oriented.width
        let scaleY = renderSize.height / oriented.height
        let scale = min(scaleX, scaleY)
        let offsetX = (renderSize.width - oriented.width * scale) / 2.0
        let offsetY = (renderSize.height - oriented.height * scale) / 2.0
        // Scale all components of the affine transform, then add centering offset
        var t = preferredTransform
        t.a *= scale; t.b *= scale
        t.c *= scale; t.d *= scale
        t.tx = t.tx * scale + offsetX
        t.ty = t.ty * scale + offsetY
        return t
    }
}
