import SwiftUI
import PhotosUI
import AVFoundation

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPicked: (URL, TimeInterval) -> Void
    var onDismissed: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onDismissed: onDismissed) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL, TimeInterval) -> Void
        let onDismissed: () -> Void

        init(onPicked: @escaping (URL, TimeInterval) -> Void, onDismissed: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onDismissed = onDismissed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                DispatchQueue.main.async { self.onDismissed() }
                return
            }
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                guard let url, error == nil else {
                    DispatchQueue.main.async { self.onDismissed() }
                    return
                }
                let destination = newClipURL()
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    DispatchQueue.main.async { self.onDismissed() }
                    return
                }
                Task {
                    do {
                        let asset = AVURLAsset(url: destination)
                        let duration = try await asset.load(.duration)
                        await MainActor.run {
                            self.onPicked(destination, duration.seconds)
                            self.onDismissed()
                        }
                    } catch {
                        await MainActor.run { self.onDismissed() }
                    }
                }
            }
        }
    }
}
