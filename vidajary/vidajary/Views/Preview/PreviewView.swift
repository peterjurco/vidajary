import SwiftUI
import AVKit
import AVFoundation
import SwiftData

struct PreviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var project: Project

    @State private var player: AVPlayer?
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var exportError: String?
    @State private var showLibraryPicker = false
    @State private var isPlaying = false
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var isEditing = false

    var sortedClips: [Clip] {
        project.clips.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Button { isEditing.toggle() } label: {
                        Image(systemName: isEditing ? "checkmark.circle" : "arrow.up.arrow.down")
                            .font(.system(size: 20))
                            .foregroundStyle(isEditing ? .white : .white.opacity(0.6))
                    }
                    Button { showLibraryPicker = true } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)

                ZStack {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white).frame(maxHeight: .infinity)
                    }

                    if !isPlaying {
                        Button {
                            player?.play()
                            isPlaying = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.black.opacity(0.4))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                // Clip list with swipe-to-delete
                List {
                    ForEach(sortedClips) { clip in
                        HStack {
                            if let thumbnail = thumbnails[clip.id] {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 40)
                                    .clipped()
                                    .cornerRadius(4)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                Text(formattedDuration(clip.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .onDelete(perform: deleteClips)
                    .onMove(perform: reorderClips)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .frame(maxHeight: 200)
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))

                Button {
                    Task { await exportVideo() }
                } label: {
                    Group {
                        if isExporting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Export to Library")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white.opacity(0.15))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .disabled(isExporting || sortedClips.isEmpty)
            }
        }
        .task {
            initializeSortOrdersIfNeeded()
            await rebuildPlayer()
        }
        .onAppear {
            Task { await detectOrientationFromFirstClip() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
            isPlaying = false
        }
        .onDisappear {
            applyOrientation(landscape: false)
        }
        .alert("Saved to Library", isPresented: $showExportSuccess) {
            Button("OK") {}
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showLibraryPicker) {
            LibraryPickerView { url, duration in
                let clip = Clip(filename: url.lastPathComponent, duration: duration, sortOrder: project.clips.count)
                project.clips.append(clip)
                project.lastRecordedAt = Date()
                try? context.save()
                Task { await rebuildPlayer() }
            } onDismissed: {
                showLibraryPicker = false
            }
        }
    }

    private func rebuildPlayer() async {
        do {
            let musicURL = project.musicFilename.map { clipsDirectory().appendingPathComponent($0) }
            let result = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory(),
                musicURL: musicURL,
                musicVolume: project.musicVolume,
                videoVolume: project.videoVolume
            )
            let item = AVPlayerItem(asset: result.composition)
            item.videoComposition = result.videoComposition
            item.audioMix = result.audioMix
            player = AVPlayer(playerItem: item)
            isPlaying = false
        } catch {
            exportError = error.localizedDescription
        }
        await loadThumbnails()
    }

    private func loadThumbnails() async {
        let dir = clipsDirectory()
        for clip in sortedClips {
            let url = dir.appendingPathComponent(clip.filename)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 80)
            do {
                let (cgImage, _) = try await generator.image(at: .zero)
                thumbnails[clip.id] = UIImage(cgImage: cgImage)
            } catch {
                // Skip clips where thumbnail generation fails
            }
        }
    }

    private func exportVideo() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let musicURL = project.musicFilename.map { clipsDirectory().appendingPathComponent($0) }
            let result = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory(),
                musicURL: musicURL,
                musicVolume: project.musicVolume,
                videoVolume: project.videoVolume
            )
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try await ExportService.export(
                composition: result.composition,
                videoComposition: result.videoComposition,
                audioMix: result.audioMix,
                to: tmp
            )
            try await ExportService.saveToPhotoLibrary(url: tmp)
            try? FileManager.default.removeItem(at: tmp)
            showExportSuccess = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func initializeSortOrdersIfNeeded() {
        guard project.clips.count > 1,
              project.clips.allSatisfy({ $0.sortOrder == 0 }) else { return }
        let sorted = project.clips.sorted { $0.recordedAt < $1.recordedAt }
        for (i, clip) in sorted.enumerated() {
            clip.sortOrder = i
        }
        try? context.save()
    }

    private func reorderClips(from source: IndexSet, to destination: Int) {
        var clips = sortedClips
        clips.move(fromOffsets: source, toOffset: destination)
        for (index, clip) in clips.enumerated() {
            clip.sortOrder = index
        }
        try? context.save()
        Task { await rebuildPlayer() }
    }

    private func deleteClips(at offsets: IndexSet) {
        let dir = clipsDirectory()
        let toDelete = offsets.map { sortedClips[$0] }
        for clip in toDelete {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(clip.filename))
            project.clips.removeAll { $0.id == clip.id }
        }
        try? context.save()
        Task { await rebuildPlayer() }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func detectOrientationFromFirstClip() async {
        guard let firstClip = sortedClips.first else { return }
        let url = clipsDirectory().appendingPathComponent(firstClip.filename)
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let isRotated = abs(transform.b) > 0.5
        let orientedWidth = isRotated ? naturalSize.height : naturalSize.width
        let orientedHeight = isRotated ? naturalSize.width : naturalSize.height
        applyOrientation(landscape: orientedWidth > orientedHeight)
    }

    private func applyOrientation(landscape: Bool) {
        AppDelegate.orientationMask = landscape ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.windows.forEach { window in
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = current.presentedViewController
            }
        }
        let orientations: UIInterfaceOrientationMask = landscape ? .landscape : .portrait
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}
