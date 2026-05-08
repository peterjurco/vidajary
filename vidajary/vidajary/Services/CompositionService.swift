import AVFoundation

struct CompositionResult {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
    let audioMix: AVMutableAudioMix?
    let clipRanges: [(id: UUID, start: CMTime, end: CMTime)]
}

enum CompositionService {

    // URL-based overload used by tests — no clip metadata, no audio mix
    static func buildComposition(from clipURLs: [URL]) async throws -> CompositionResult {
        let composition = AVMutableComposition()
        guard !clipURLs.isEmpty else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var audioInserted = false
        var cursor = CMTime.zero
        var renderSize: CGSize?
        var frameRate: Float = 30
        var clipInfos: [(timeRange: CMTimeRange, naturalSize: CGSize, preferredTransform: CGAffineTransform, rotationOverride: Int)] = []

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
                    renderSize = finalDisplaySize(naturalSize: naturalSize, transform: preferredTransform, rotationOverride: 0)
                    frameRate = try await srcVideo.load(.nominalFrameRate)
                }
                clipInfos.append((
                    timeRange: CMTimeRange(start: cursor, duration: duration),
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    rotationOverride: 0
                ))
            }
            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                audioInserted = true
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        if !audioInserted, let at = audioTrack { composition.removeTrack(at) }

        guard let renderSize, !clipInfos.isEmpty else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        let videoComposition = buildVideoComposition(
            videoTrack: videoTrack,
            clipInfos: clipInfos,
            renderSize: renderSize,
            frameRate: frameRate,
            totalDuration: cursor
        )

        return CompositionResult(composition: composition, videoComposition: videoComposition, audioMix: nil, clipRanges: [])
    }

    // Clip-based overload used by the app — full metadata support
    static func buildComposition(
        from clips: [Clip],
        in directory: URL,
        musicURL: URL? = nil
    ) async throws -> CompositionResult {
        let sortedClips = clips.sorted { $0.sortOrder < $1.sortOrder }
        let composition = AVMutableComposition()

        guard !sortedClips.isEmpty else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        struct ClipTimelineInfo {
            let startTime: CMTime
            let endTime: CMTime
            let clipVolume: Float
            let musicVolume: Float
            let hasAudio: Bool
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var audioInserted = false
        var cursor = CMTime.zero
        var renderSize: CGSize?
        var frameRate: Float = 30
        var clipInfos: [(timeRange: CMTimeRange, naturalSize: CGSize, preferredTransform: CGAffineTransform, rotationOverride: Int)] = []
        var clipTimelineInfos: [ClipTimelineInfo] = []

        for clip in sortedClips {
            let url = directory.appendingPathComponent(clip.filename)
            let asset = AVURLAsset(url: url)
            let fullDuration = try await asset.load(.duration)
            guard fullDuration.isValid, fullDuration.seconds > 0 else { continue }

            let trimStartTime = CMTimeMakeWithSeconds(clip.trimStart, preferredTimescale: 600)
            let trimEndSeconds = clip.trimEnd > 0 ? clip.trimEnd : fullDuration.seconds
            let trimEndTime = CMTimeMakeWithSeconds(trimEndSeconds, preferredTimescale: 600)
            let trimmedDuration = CMTimeSubtract(trimEndTime, trimStartTime)
            guard trimmedDuration.seconds > 0 else { continue }
            let sourceRange = CMTimeRange(start: trimStartTime, duration: trimmedDuration)

            if let srcVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(sourceRange, of: srcVideo, at: cursor)
                let naturalSize = try await srcVideo.load(.naturalSize)
                let preferredTransform = try await srcVideo.load(.preferredTransform)
                if renderSize == nil {
                    renderSize = finalDisplaySize(
                        naturalSize: naturalSize,
                        transform: preferredTransform,
                        rotationOverride: clip.rotationOverride
                    )
                    frameRate = try await srcVideo.load(.nominalFrameRate)
                }
                clipInfos.append((
                    timeRange: CMTimeRange(start: cursor, duration: trimmedDuration),
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    rotationOverride: clip.rotationOverride
                ))
            }

            var hasAudio = false
            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(sourceRange, of: srcAudio, at: cursor)
                audioInserted = true
                hasAudio = true
            }

            let clipStart = cursor
            cursor = CMTimeAdd(cursor, trimmedDuration)

            clipTimelineInfos.append(ClipTimelineInfo(
                startTime: clipStart,
                endTime: cursor,
                clipVolume: clip.clipVolume,
                musicVolume: clip.musicVolume,
                hasAudio: hasAudio
            ))
        }

        if !audioInserted, let at = audioTrack { composition.removeTrack(at) }

        // Music track
        var musicCompositionTrack: AVMutableCompositionTrack? = nil
        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            if let srcMusic = try? await musicAsset.loadTracks(withMediaType: .audio).first {
                let musicDuration = try await musicAsset.load(.duration)
                let effectiveMusicDuration = CMTimeMinimum(musicDuration, cursor)
                let mt = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                )
                try mt?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: effectiveMusicDuration),
                    of: srcMusic, at: .zero
                )
                musicCompositionTrack = mt
            }
        }

        guard let renderSize, !clipInfos.isEmpty else {
            return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil, clipRanges: [])
        }

        let videoComposition = buildVideoComposition(
            videoTrack: videoTrack,
            clipInfos: clipInfos,
            renderSize: renderSize,
            frameRate: frameRate,
            totalDuration: cursor
        )

        // Build audioMix
        let needsAudioMix = audioInserted || musicCompositionTrack != nil
        var audioMix: AVMutableAudioMix? = nil
        if needsAudioMix {
            var params: [AVMutableAudioMixInputParameters] = []

            // Per-clip volume automation on the single merged audio track.
            // setVolume ramps between keyframes, so we pin each clip's volume just
            // before its boundary to make transitions instantaneous.
            if audioInserted, let track = audioTrack {
                let p = AVMutableAudioMixInputParameters()
                p.trackID = track.trackID
                let oneSample = CMTime(value: 1, timescale: 44100)
                for info in clipTimelineInfos where info.hasAudio {
                    p.setVolume(info.clipVolume, at: info.startTime)
                    let pinTime = CMTimeSubtract(info.endTime, oneSample)
                    if CMTimeCompare(pinTime, info.startTime) > 0 {
                        p.setVolume(info.clipVolume, at: pinTime)
                    }
                }
                params.append(p)
            }

            // Music volume automation with 0.3s ramps at level-changing boundaries
            if let mt = musicCompositionTrack {
                let p = AVMutableAudioMixInputParameters()
                p.trackID = mt.trackID
                let rampDuration = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)

                if let first = clipTimelineInfos.first {
                    p.setVolume(first.musicVolume, at: .zero)
                }
                for i in 1..<clipTimelineInfos.count {
                    let prev = clipTimelineInfos[i - 1]
                    let curr = clipTimelineInfos[i]
                    if prev.musicVolume != curr.musicVolume {
                        p.setVolumeRamp(
                            fromStartVolume: prev.musicVolume,
                            toEndVolume: curr.musicVolume,
                            timeRange: CMTimeRange(start: curr.startTime, duration: rampDuration)
                        )
                    }
                }
                params.append(p)
            }

            let mix = AVMutableAudioMix()
            mix.inputParameters = params
            audioMix = mix
        }

        let clipRanges = zip(sortedClips, clipTimelineInfos).map { clip, info in
            (id: clip.id, start: info.startTime, end: info.endTime)
        }

        return CompositionResult(composition: composition, videoComposition: videoComposition, audioMix: audioMix, clipRanges: clipRanges)
    }

    // MARK: - Private helpers

    private static func buildVideoComposition(
        videoTrack: AVMutableCompositionTrack,
        clipInfos: [(timeRange: CMTimeRange, naturalSize: CGSize, preferredTransform: CGAffineTransform, rotationOverride: Int)],
        renderSize: CGSize,
        frameRate: Float,
        totalDuration: CMTime
    ) -> AVMutableVideoComposition {
        let vc = AVMutableVideoComposition()
        vc.renderSize = renderSize
        let safeFrameRate = max(1, Int32(frameRate.rounded()))
        vc.frameDuration = CMTime(value: 1, timescale: safeFrameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        for info in clipInfos {
            let t = fitTransform(
                naturalSize: info.naturalSize,
                preferredTransform: info.preferredTransform,
                rotationOverride: info.rotationOverride,
                renderSize: renderSize
            )
            layerInstruction.setTransform(t, at: info.timeRange.start)
        }

        instruction.layerInstructions = [layerInstruction]
        vc.instructions = [instruction]
        return vc
    }

    static func orientedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let isRotated = abs(transform.b) > 0.5
        return isRotated
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize
    }

    static func finalDisplaySize(naturalSize: CGSize, transform: CGAffineTransform, rotationOverride: Int) -> CGSize {
        let oriented = orientedSize(naturalSize: naturalSize, transform: transform)
        let swapDimensions = (rotationOverride / 90) % 2 != 0
        return swapDimensions
            ? CGSize(width: oriented.height, height: oriented.width)
            : oriented
    }

    // Maps natural video coords -> composition render coords, incorporating
    // preferredTransform (camera orientation) + rotationOverride + scale/center.
    static func fitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        rotationOverride: Int,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let oriented = orientedSize(naturalSize: naturalSize, transform: preferredTransform)
        let angle = CGFloat(rotationOverride) * .pi / 180.0
        let swapDimensions = (rotationOverride / 90) % 2 != 0
        let finalSize: CGSize = swapDimensions
            ? CGSize(width: oriented.height, height: oriented.width)
            : oriented
        let scale = min(renderSize.width / finalSize.width, renderSize.height / finalSize.height)
        let cx = oriented.width / 2
        let cy = oriented.height / 2
        let correctionX = finalSize.width / 2 - cx
        let correctionY = finalSize.height / 2 - cy
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -cx, y: -cy))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: cx + correctionX, y: cy + correctionY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (renderSize.width - finalSize.width * scale) / 2.0,
                y: (renderSize.height - finalSize.height * scale) / 2.0
            ))
    }
}
