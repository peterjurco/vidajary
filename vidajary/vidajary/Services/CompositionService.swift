import AVFoundation

enum CompositionService {

    /// Builds an in-memory composition from an ordered list of clip file URLs.
    static func buildComposition(from clipURLs: [URL]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard !clipURLs.isEmpty else { return composition }

        let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var audioTrack: AVMutableCompositionTrack? = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var audioInserted = false

        var cursor = CMTime.zero

        for url in clipURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isValid, duration.seconds > 0 else { continue }
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let srcVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(timeRange, of: srcVideo, at: cursor)
            }
            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                audioInserted = true
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        // Remove the audio track if no clip contributed audio
        if !audioInserted, let audioTrack {
            composition.removeTrack(audioTrack)
        }

        return composition
    }

    /// Convenience overload: builds from Clip models given the directory containing clip files.
    static func buildComposition(from clips: [Clip], in directory: URL) async throws -> AVMutableComposition {
        let urls = clips
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { directory.appendingPathComponent($0.filename) }
        return try await buildComposition(from: urls)
    }
}
