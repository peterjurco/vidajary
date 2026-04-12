import AVFoundation
import Photos

enum ExportService {

    enum ExportError: LocalizedError {
        case sessionCreationFailed
        case exportFailed(String?)
        case photoLibraryAccessDenied

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed: return "Could not create export session."
            case .exportFailed(let msg): return msg ?? "Export failed."
            case .photoLibraryAccessDenied: return "Photo library access was denied."
            }
        }
    }

    /// Exports the composition to a file at `outputURL`.
    static func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition? = nil,
        audioMix: AVMutableAudioMix? = nil,
        to outputURL: URL
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ExportError.sessionCreationFailed }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        session.videoComposition = videoComposition
        session.audioMix = audioMix

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }

        if let error = session.error { throw error }
        guard session.status == .completed else {
            throw ExportError.exportFailed(session.error?.localizedDescription)
        }
    }

    /// Saves a video file to the user's Photos library.
    static func saveToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoLibraryAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
