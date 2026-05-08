import SwiftUI
import PhotosUI
import AVFoundation

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPicked: ([(URL, TimeInterval)]) -> Void
    var onDismissed: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onDismissed: onDismissed) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([(URL, TimeInterval)]) -> Void
        let onDismissed: () -> Void

        init(onPicked: @escaping ([(URL, TimeInterval)]) -> Void, onDismissed: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onDismissed = onDismissed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss via SwiftUI binding — do NOT call picker.dismiss(animated:) as it can
            // walk the UIKit VC hierarchy and inadvertently close the parent fullScreenCover.
            DispatchQueue.main.async { self.onDismissed() }
            guard !results.isEmpty else { return }
            Task {
                var clips: [(URL, TimeInterval)] = []
                for result in results {
                    if let clip = await Self.loadVideo(from: result) {
                        clips.append(clip)
                    }
                }
                if !clips.isEmpty {
                    await MainActor.run { self.onPicked(clips) }
                }
            }
        }

        private static func loadVideo(from result: PHPickerResult) async -> (URL, TimeInterval)? {
            await withCheckedContinuation { continuation in
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
                            continuation.resume(returning: (destination, duration.seconds))
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
}
