import SwiftUI
import PhotosUI
import AVFoundation

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPicked: ([(URL, TimeInterval, Date)]) -> Void
    var onDismissed: () -> Void
    var onImportStarted: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
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

            return await withCheckedContinuation { continuation in
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                    guard let url, error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let destination = newClipURL()
                    do {
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch {
                        continuation.resume(returning: nil)
                        return
                    }
                    Task {
                        do {
                            let asset = AVURLAsset(url: destination)
                            let duration = try await asset.load(.duration)
                            continuation.resume(returning: (destination, duration.seconds, creationDate))
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
}
