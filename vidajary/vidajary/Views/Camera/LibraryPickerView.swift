import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPicked: ([(URL, TimeInterval, Date)]) -> Void
    var onDismissed: () -> Void
    var onImportStarted: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.videos, .livePhotos])
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onImportStarted: onImportStarted, onDismissed: onDismissed) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([(URL, TimeInterval, Date)]) -> Void
        let onImportStarted: () -> Void
        let onDismissed: () -> Void

        init(onPicked: @escaping ([(URL, TimeInterval, Date)]) -> Void,
             onImportStarted: @escaping () -> Void,
             onDismissed: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onImportStarted = onImportStarted
            self.onDismissed = onDismissed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            DispatchQueue.main.async { self.onDismissed() }
            guard !results.isEmpty else { return }
            DispatchQueue.main.async { self.onImportStarted() }
            Task {
                var clips: [(URL, TimeInterval, Date)] = []
                for result in results {
                    if let clip = await Self.loadVideo(from: result) {
                        clips.append(clip)
                    }
                }
                await MainActor.run { self.onPicked(clips) }
            }
        }

        private static func loadVideo(from result: PHPickerResult) async -> (URL, TimeInterval, Date)? {
            let creationDate: Date = {
                guard let identifier = result.assetIdentifier else { return Date() }
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                return assets.firstObject?.creationDate ?? Date()
            }()

            let provider = result.itemProvider
            let destination: URL?
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                destination = await copyMovie(from: provider)
            } else if provider.canLoadObject(ofClass: PHLivePhoto.self) {
                destination = await extractLivePhotoVideo(from: provider)
            } else {
                destination = nil
            }

            guard let destination else { return nil }
            do {
                let duration = try await AVURLAsset(url: destination).load(.duration)
                return (destination, duration.seconds, creationDate)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
        }

        private static func copyMovie(from provider: NSItemProvider) async -> URL? {
            await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url, error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let destination = newClipURL()
                    do {
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume(returning: destination)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        /// Writes the video part of a Live Photo to a new clip file.
        private static func extractLivePhotoVideo(from provider: NSItemProvider) async -> URL? {
            let livePhoto: PHLivePhoto? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: PHLivePhoto.self) { object, _ in
                    continuation.resume(returning: object as? PHLivePhoto)
                }
            }
            guard let livePhoto,
                  let videoResource = PHAssetResource.assetResources(for: livePhoto)
                    .first(where: { $0.type == .pairedVideo })
            else { return nil }

            let destination = newClipURL()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            return await withCheckedContinuation { continuation in
                PHAssetResourceManager.default().writeData(for: videoResource, toFile: destination, options: options) { error in
                    if error != nil {
                        try? FileManager.default.removeItem(at: destination)
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: destination)
                    }
                }
            }
        }
    }
}
