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
    @State private var exportProgress: Float = 0
    @State private var showExportSuccess = false
    @State private var exportError: String?
    @State private var showLibraryPicker = false
    @State private var showMusicPickerSheet = false
    @State private var isPlaying = false
    @State private var isRebuildingPlayer = false
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var isEditing = false
    @State private var clipToEdit: Clip?
    @State private var currentClipID: UUID?
    @State private var timeObserverToken: Any?
    @State private var clipRanges: [(id: UUID, start: CMTime, end: CMTime)] = []

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
                    Button { showMusicPickerSheet = true } label: {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
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
                            .frame(height: 260)
                    } else {
                        Color.black.frame(height: 260)
                    }

                    if isRebuildingPlayer {
                        Color.black.opacity(0.5).frame(height: 260)
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Generating preview…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else if !isPlaying {
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
                ScrollViewReader { proxy in
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
                                    Text(formattedDuration((clip.trimEnd > 0 ? clip.trimEnd : clip.duration) - clip.trimStart))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    if let range = clipRanges.first(where: { $0.id == clip.id }) {
                                        player?.seek(to: range.start)
                                        player?.play()
                                        isPlaying = true
                                    }
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 32, height: 44)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    player?.pause()
                                    isPlaying = false
                                    clipToEdit = clip
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 36, height: 44)
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(.white)
                            .id(clip.id)
                            .listRowBackground(
                                clip.id == currentClipID
                                    ? Color.white.opacity(0.12)
                                    : Color.black
                            )
                        }
                        .onDelete(perform: deleteClips)
                        .onMove(perform: reorderClips)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                    .frame(maxHeight: .infinity)
                    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                    .onChange(of: currentClipID) { _, newID in
                        guard let id = newID else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }

                Button {
                    Task { await exportVideo() }
                } label: {
                    GeometryReader { geo in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.15))
                            if isExporting {
                                HStack(spacing: 0) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(exportProgress))
                                    Spacer(minLength: 0)
                                }
                                .animation(.easeInOut(duration: 0.15), value: exportProgress)
                            }
                            if isExporting {
                                Text("Exporting… \(Int(exportProgress * 100))%")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                            } else {
                                Text("Export to Library")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
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
            stopTimeObserver()
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
        .fullScreenCover(item: $clipToEdit) { clip in
            ClipEditView(
                clip: clip,
                clipURL: clipsDirectory().appendingPathComponent(clip.filename),
                project: project
            )
            .onDisappear {
                Task { await rebuildPlayer() }
            }
        }
        .sheet(isPresented: $showMusicPickerSheet) {
            MusicPickerSheet(project: project) {
                Task { await rebuildPlayer() }
            }
        }
        .sheet(isPresented: $showLibraryPicker) {
            LibraryPickerView { clips in
                for (url, duration) in clips {
                    let clip = Clip(filename: url.lastPathComponent, duration: duration, sortOrder: project.clips.count)
                    project.clips.append(clip)
                }
                project.lastRecordedAt = Date()
                try? context.save()
                Task { await rebuildPlayer() }
            } onDismissed: {
                showLibraryPicker = false
            }
        }
    }

    private func rebuildPlayer() async {
        stopTimeObserver()
        let preservedTime = player?.currentTime()
        isRebuildingPlayer = true
        defer { isRebuildingPlayer = false }
        do {
            let musicURL = project.musicFilename.map { clipsDirectory().appendingPathComponent($0) }
            let result = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory(),
                musicURL: musicURL
            )
            let item = AVPlayerItem(asset: result.composition)
            item.videoComposition = result.videoComposition
            item.audioMix = result.audioMix
            if let existingPlayer = player {
                existingPlayer.replaceCurrentItem(with: item)
            } else {
                player = AVPlayer(playerItem: item)
            }
            if let time = preservedTime, time.isValid, time.seconds > 0 {
                await player?.seek(to: time)
            }
            clipRanges = result.clipRanges
            isPlaying = false
            startTimeObserver()
        } catch {
            exportError = error.localizedDescription
        }
        await loadThumbnails()
    }

    private func startTimeObserver() {
        guard let player else { return }
        let ranges = clipRanges
        let interval = CMTime(value: 1, timescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let found = ranges.first {
                CMTimeCompare(time, $0.start) >= 0 && CMTimeCompare(time, $0.end) < 0
            }
            currentClipID = found?.id ?? ranges.last?.id
        }
    }

    private func stopTimeObserver() {
        guard let token = timeObserverToken else { return }
        player?.removeTimeObserver(token)
        timeObserverToken = nil
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
                let image = UIImage(cgImage: cgImage)
                thumbnails[clip.id] = clip.rotationOverride == 0 ? image : image.rotated(by: clip.rotationOverride)
            } catch {
                // Skip clips where thumbnail generation fails
            }
        }
    }

    private func exportVideo() async {
        isExporting = true
        exportProgress = 0
        defer {
            isExporting = false
            exportProgress = 0
        }
        do {
            let musicURL = project.musicFilename.map { clipsDirectory().appendingPathComponent($0) }
            let result = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory(),
                musicURL: musicURL
            )
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try await ExportService.export(
                composition: result.composition,
                videoComposition: result.videoComposition,
                audioMix: result.audioMix,
                to: tmp,
                onProgress: { [self] p in exportProgress = p }
            )
            try await ExportService.saveToPhotoLibrary(url: tmp)
            try? FileManager.default.removeItem(at: tmp)
            showExportSuccess = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func initializeSortOrdersIfNeeded() {
        guard !project.clips.isEmpty,
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

private extension UIImage {
    func rotated(by degrees: Int) -> UIImage {
        guard degrees != 0 else { return self }
        let radians = CGFloat(degrees) * .pi / 180
        let newSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        return UIGraphicsImageRenderer(size: newSize).image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
