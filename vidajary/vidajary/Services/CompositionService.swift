import AVFoundation

enum CompositionService {

    /// Builds an in-memory composition from an ordered list of clip file URLs.
    static func buildComposition(from clipURLs: [URL]) throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard !clipURLs.isEmpty else { return composition }

        let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero

        for url in clipURLs {
            let asset = AVURLAsset(url: url)
            let duration = asset.duration
            guard duration.isValid, duration.seconds > 0 else { continue }
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let srcVideo = asset.tracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(timeRange, of: srcVideo, at: cursor)
            }
            if let srcAudio = asset.tracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: srcAudio, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        return composition
    }

    /// Convenience overload: builds from Clip models given the directory containing clip files.
    static func buildComposition(from clips: [Clip], in directory: URL) throws -> AVMutableComposition {
        let urls = clips
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { directory.appendingPathComponent($0.filename) }
        return try buildComposition(from: urls)
    }
}
