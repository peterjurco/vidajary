# Audio Controls Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all volume controls into a per-clip editor, add a top-toolbar music picker icon, and simplify the bottom bar to just the export button.

**Architecture:** Each clip gets its own AVMutableCompositionTrack for audio (enabling per-clip volume). Background music automation uses setVolumeRamp at boundaries where adjacent clips differ. A new ClipEditView (full-screen) replaces both ClipTrimView and the per-clip rotate/scissors buttons. A new MusicPickerSheet handles add/remove background music from the top toolbar.

**Tech Stack:** SwiftUI, SwiftData, AVFoundation, AVKit

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Models/Clip.swift` | Modify | Add `clipVolume` and `musicVolume` fields |
| `Services/CompositionService.swift` | Modify | Per-clip audio tracks, music volume automation, remove old volume params |
| `Views/Preview/ClipEditView.swift` | Create | Full-screen clip editor: trim, rotation, clip volume, music volume |
| `Views/Preview/MusicPickerSheet.swift` | Create | Sheet for add/remove background music |
| `Views/Preview/PreviewView.swift` | Modify | Remove bottom audio controls, add music icon, replace clip buttons |
| `Views/Preview/ClipTrimView.swift` | Delete | Logic moved into ClipEditView |
| `vidajaryTests/ModelTests.swift` | Modify | Tests for new Clip fields |

---

## Task 1: Add clipVolume and musicVolume to Clip

**Files:**
- Modify: `vidajary/vidajary/Models/Clip.swift`
- Modify: `vidajary/vidajaryTests/ModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ModelTests.swift` after `testClipEffectiveDuration`:

```swift
func testClipVolumeDefaults() throws {
    let clip = Clip(filename: "test.mov", duration: 10.0)
    XCTAssertEqual(clip.clipVolume, 1.0, accuracy: 0.001)
    XCTAssertEqual(clip.musicVolume, 1.0, accuracy: 0.001)
}

func testClipVolumesPersist() throws {
    let project = Project(name: "Test")
    context.insert(project)
    let clip = Clip(filename: "a.mov", duration: 5.0)
    clip.clipVolume = 0.5
    clip.musicVolume = 0.3
    project.clips.append(clip)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Clip>()).first!
    XCTAssertEqual(fetched.clipVolume, 0.5, accuracy: 0.001)
    XCTAssertEqual(fetched.musicVolume, 0.3, accuracy: 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

In Xcode, run the `vidajaryTests` target. Expected: compile error — `clipVolume` and `musicVolume` are not members of `Clip`.

- [ ] **Step 3: Add the fields to Clip.swift**

Replace the fields block in `Models/Clip.swift`:

```swift
@Model
final class Clip {
    var id: UUID
    var filename: String
    var recordedAt: Date
    var duration: TimeInterval
    var project: Project?
    var sortOrder: Int = 0
    var rotationOverride: Int = 0   // 0, 90, 180, or 270
    var trimStart: TimeInterval = 0 // seconds from clip start; 0 = no trim
    var trimEnd: TimeInterval = 0   // seconds from clip start; 0 = use full duration
    var clipVolume: Float = 1.0     // this clip's audio volume (0–1)
    var musicVolume: Float = 1.0    // background music level during this clip (0–1)

    init(filename: String, duration: TimeInterval, sortOrder: Int = 0) {
        self.id = UUID()
        self.filename = filename
        self.recordedAt = Date()
        self.duration = duration
        self.sortOrder = sortOrder
        self.rotationOverride = 0
        self.trimStart = 0
        self.trimEnd = 0
    }

    var effectiveDuration: TimeInterval {
        let end = trimEnd > 0 ? trimEnd : duration
        return max(0, end - trimStart)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `vidajaryTests`. Expected: `testClipVolumeDefaults` and `testClipVolumesPersist` pass.

- [ ] **Step 5: Commit**

```bash
git add vidajary/vidajary/Models/Clip.swift vidajary/vidajaryTests/ModelTests.swift
git commit -m "feat: add clipVolume and musicVolume fields to Clip"
```

---

## Task 2: Update CompositionService

**Files:**
- Modify: `vidajary/vidajary/Services/CompositionService.swift`

Replace the entire clip-based `buildComposition` overload (lines 79–206). The URL-based overload and all private helpers remain untouched.

- [ ] **Step 1: Replace the clip-based overload**

Replace the function starting at `// Clip-based overload used by the app` through its closing `}` with:

```swift
// Clip-based overload used by the app — full metadata support
static func buildComposition(
    from clips: [Clip],
    in directory: URL,
    musicURL: URL? = nil
) async throws -> CompositionResult {
    let sortedClips = clips.sorted { $0.sortOrder < $1.sortOrder }
    let composition = AVMutableComposition()

    guard !sortedClips.isEmpty else {
        return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil)
    }

    guard let videoTrack = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil)
    }

    struct ClipTimelineInfo {
        let startTime: CMTime
        let duration: CMTime
        let clipVolume: Float
        let musicVolume: Float
        let audioTrack: AVMutableCompositionTrack?
    }

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

        var clipAudioTrack: AVMutableCompositionTrack? = nil
        if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
            let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try track?.insertTimeRange(sourceRange, of: srcAudio, at: cursor)
            clipAudioTrack = track
        }

        clipTimelineInfos.append(ClipTimelineInfo(
            startTime: cursor,
            duration: trimmedDuration,
            clipVolume: clip.clipVolume,
            musicVolume: clip.musicVolume,
            audioTrack: clipAudioTrack
        ))

        cursor = CMTimeAdd(cursor, trimmedDuration)
    }

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
        return CompositionResult(composition: composition, videoComposition: nil, audioMix: nil)
    }

    let videoComposition = buildVideoComposition(
        videoTrack: videoTrack,
        clipInfos: clipInfos,
        renderSize: renderSize,
        frameRate: frameRate,
        totalDuration: cursor
    )

    // Build audioMix
    let hasClipAudio = clipTimelineInfos.contains { $0.audioTrack != nil }
    let needsAudioMix = hasClipAudio || musicCompositionTrack != nil
    var audioMix: AVMutableAudioMix? = nil
    if needsAudioMix {
        var params: [AVMutableAudioMixInputParameters] = []

        // Per-clip audio volume
        for info in clipTimelineInfos {
            guard let track = info.audioTrack else { continue }
            let p = AVMutableAudioMixInputParameters()
            p.trackID = track.trackID
            p.setVolume(info.clipVolume, at: info.startTime)
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

    return CompositionResult(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
}
```

- [ ] **Step 2: Build the project**

Build in Xcode (⌘B). Expected: compile errors in `PreviewView.swift` — `buildComposition` called with extra `musicVolume` and `videoVolume` arguments. These will be fixed in Task 5.

- [ ] **Step 3: Commit**

```bash
git add vidajary/vidajary/Services/CompositionService.swift
git commit -m "feat: per-clip audio tracks and music volume automation in CompositionService"
```

---

## Task 3: Create MusicPickerSheet

**Files:**
- Create: `vidajary/vidajary/Views/Preview/MusicPickerSheet.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct MusicPickerSheet: View {
    var project: Project
    let onChanged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let musicName = project.musicFilename {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                        Text(String(musicName.prefix(40)) + (musicName.count > 40 ? "…" : ""))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            removeMusic()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Add Background Music", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Background Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): importMusic(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func importMusic(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let filename = UUID().uuidString + "." + url.pathExtension
        let dest = clipsDirectory().appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            errorMessage = "Failed to import music: \(error.localizedDescription)"
            return
        }
        if let old = project.musicFilename {
            try? FileManager.default.removeItem(at: clipsDirectory().appendingPathComponent(old))
        }
        project.musicFilename = filename
        try? context.save()
        onChanged()
    }

    private func removeMusic() {
        if let old = project.musicFilename {
            try? FileManager.default.removeItem(at: clipsDirectory().appendingPathComponent(old))
        }
        project.musicFilename = nil
        try? context.save()
        onChanged()
    }
}
```

- [ ] **Step 2: Build the project**

Build in Xcode (⌘B). Expected: no new errors from this file.

- [ ] **Step 3: Commit**

```bash
git add "vidajary/vidajary/Views/Preview/MusicPickerSheet.swift"
git commit -m "feat: add MusicPickerSheet for background music management"
```

---

## Task 4: Create ClipEditView

**Files:**
- Create: `vidajary/vidajary/Views/Preview/ClipEditView.swift`

This view absorbs all logic from `ClipTrimView` and adds rotation, clip volume, and music volume controls.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import AVKit
import AVFoundation
import SwiftData

struct ClipEditView: View {
    var clip: Clip
    let clipURL: URL
    var project: Project

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var filmstrip: [UIImage] = []
    @State private var isPlaying = false
    @State private var playerItem: AVPlayerItem?

    @State private var localTrimStart: TimeInterval
    @State private var localTrimEnd: TimeInterval
    @State private var localRotation: Int
    @State private var localClipVolume: Float
    @State private var localMusicVolume: Float

    init(clip: Clip, clipURL: URL, project: Project) {
        self.clip = clip
        self.clipURL = clipURL
        self.project = project
        _localTrimStart = State(initialValue: clip.trimStart)
        _localTrimEnd = State(
            initialValue: min(clip.duration, clip.trimEnd > 0 ? clip.trimEnd : clip.duration)
        )
        _localRotation = State(initialValue: clip.rotationOverride)
        _localClipVolume = State(initialValue: clip.clipVolume)
        _localMusicVolume = State(initialValue: clip.musicVolume)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {

                // Navigation bar
                HStack {
                    Button("Cancel") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(height: 44)
                    Spacer()
                    Text("Edit Clip")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Done") {
                        clip.trimStart = localTrimStart
                        clip.trimEnd = localTrimEnd
                        clip.rotationOverride = localRotation
                        clip.clipVolume = localClipVolume
                        clip.musicVolume = localMusicVolume
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(.yellow)
                    .frame(height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Video preview
                ZStack {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white).frame(maxHeight: .infinity)
                    }
                    if !isPlaying {
                        Button {
                            player?.seek(to: CMTimeMakeWithSeconds(localTrimStart, preferredTimescale: 600))
                            player?.play()
                            isPlaying = true
                        } label: {
                            ZStack {
                                Circle().fill(.black.opacity(0.4)).frame(width: 56, height: 56)
                                Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                            }
                        }
                    }
                }

                // Filmstrip + trim handles
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        if filmstrip.isEmpty {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 60)
                        } else {
                            HStack(spacing: 0) {
                                ForEach(filmstrip.indices, id: \.self) { i in
                                    Image(uiImage: filmstrip[i])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width / CGFloat(filmstrip.count), height: 60)
                                        .clipped()
                                }
                            }
                            .cornerRadius(6)
                        }

                        let startFraction = CGFloat(localTrimStart / clip.duration)
                        let endFraction = CGFloat(localTrimEnd / clip.duration)
                        let startX = startFraction * geo.size.width
                        let endX = endFraction * geo.size.width

                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: startX, height: 60)

                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, geo.size.width - endX), height: 60)
                            .offset(x: endX)

                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: 60)
                            .offset(x: startX)

                        TrimHandle()
                            .offset(x: max(0, startX - 4))
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let t = max(0, min(localTrimEnd - 0.5,
                                        Double(value.location.x / geo.size.width) * clip.duration))
                                    localTrimStart = t
                                    isPlaying = false
                                    player?.pause()
                                    player?.seek(to: CMTimeMakeWithSeconds(t, preferredTimescale: 600))
                                }
                            )

                        TrimHandle()
                            .offset(x: max(0, min(geo.size.width - 8, endX - 4)))
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let t = min(clip.duration, max(localTrimStart + 0.5,
                                        Double(value.location.x / geo.size.width) * clip.duration))
                                    localTrimEnd = t
                                    isPlaying = false
                                    player?.pause()
                                    player?.seek(to: CMTimeMakeWithSeconds(max(0, t - 1.0), preferredTimescale: 600))
                                }
                            )
                    }
                }
                .frame(height: 68)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Trim time display
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Text(formattedTime(localTrimStart) + " – " + formattedTime(localTrimEnd))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(formattedTime(localTrimEnd - localTrimStart) + " selected")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                // Controls
                VStack(spacing: 16) {
                    // Rotation
                    HStack {
                        Image(systemName: "rotate.left")
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 20)
                        Text("Rotation")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("\(localRotation)°")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 40, alignment: .trailing)
                        Button {
                            localRotation = (localRotation + 270) % 360
                        } label: {
                            Image(systemName: "rotate.left")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.plain)
                    }

                    // Clip audio volume
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 20)
                        Text("Clip Audio")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 70, alignment: .leading)
                        Slider(value: $localClipVolume, in: 0...1)
                            .tint(.white)
                        Text("\(Int(localClipVolume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 36, alignment: .trailing)
                    }

                    // Background music volume (only shown if project has music)
                    if project.musicFilename != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20)
                            Text("BG Music")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $localMusicVolume, in: 0...1)
                                .tint(.white)
                            Text("\(Int(localMusicVolume * 100))%")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .task {
            let asset = AVURLAsset(url: clipURL)
            let item = AVPlayerItem(asset: asset)
            playerItem = item
            player = AVPlayer(playerItem: item)
            _ = await player?.seek(to: CMTimeMakeWithSeconds(localTrimStart, preferredTimescale: 600))
            await loadFilmstrip(asset: asset)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVPlayerItem.didPlayToEndTimeNotification,
                object: playerItem
            )
        ) { _ in
            isPlaying = false
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadFilmstrip(asset: AVURLAsset) async {
        guard let duration = try? await asset.load(.duration) else { return }
        let count = 8
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 80, height: 60)
        var images: [UIImage] = []
        for i in 0..<count {
            let t = CMTimeMakeWithSeconds(
                duration.seconds * Double(i) / Double(max(1, count - 1)),
                preferredTimescale: 600
            )
            if let (cgImage, _) = try? await generator.image(at: t) {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        filmstrip = images
    }

    private func formattedTime(_ t: TimeInterval) -> String {
        String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}

private struct TrimHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.yellow)
            .frame(width: 8, height: 68)
    }
}
```

- [ ] **Step 2: Build the project**

Build in Xcode (⌘B). Expected: no new errors from this file. The existing `PreviewView` errors from Task 2 are still present.

- [ ] **Step 3: Commit**

```bash
git add "vidajary/vidajary/Views/Preview/ClipEditView.swift"
git commit -m "feat: add ClipEditView with trim, rotation, clip volume, and music volume"
```

---

## Task 5: Update PreviewView

**Files:**
- Modify: `vidajary/vidajary/Views/Preview/PreviewView.swift`

This task fixes the compile errors introduced in Task 2 and wires up the new views.

- [ ] **Step 1: Replace state declarations**

Replace lines 12–22 (the `@State` block) with:

```swift
@State private var player: AVPlayer?
@State private var isExporting = false
@State private var exportProgress: Float = 0
@State private var showExportSuccess = false
@State private var exportError: String?
@State private var showLibraryPicker = false
@State private var showMusicPickerSheet = false
@State private var isPlaying = false
@State private var thumbnails: [UUID: UIImage] = [:]
@State private var isEditing = false
@State private var clipToEdit: Clip?
```

- [ ] **Step 2: Add music icon to top toolbar**

Replace the top `HStack` (lines 33–51) with:

```swift
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
```

- [ ] **Step 3: Replace per-clip row buttons**

Replace the two `Button` blocks in the clip `HStack` (the rotate and scissors buttons, lines 103–120) with:

```swift
Button {
    clipToEdit = clip
} label: {
    Image(systemName: "pencil")
        .font(.system(size: 16))
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 36, height: 44)
}
.buttonStyle(.plain)
```

- [ ] **Step 4: Remove the audio controls VStack**

Delete the entire `// Audio controls` section — the `VStack(spacing: 10)` block containing the music picker row, video volume slider, and music volume slider (lines 133–218). The export button follows immediately after the list.

- [ ] **Step 5: Replace fullScreenCover and sheet modifiers**

Replace the `.fullScreenCover(item: $clipToTrim)` block with:

```swift
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
```

Replace the `.fileImporter(isPresented: $showMusicPicker, ...)` block with:

```swift
.sheet(isPresented: $showMusicPickerSheet) {
    MusicPickerSheet(project: project) {
        Task { await rebuildPlayer() }
    }
}
```

- [ ] **Step 6: Update rebuildPlayer() and exportVideo()**

In `rebuildPlayer()`, replace the `CompositionService.buildComposition` call with:

```swift
let result = try await CompositionService.buildComposition(
    from: sortedClips,
    in: clipsDirectory(),
    musicURL: musicURL
)
```

In `exportVideo()`, replace the `CompositionService.buildComposition` call with:

```swift
let result = try await CompositionService.buildComposition(
    from: sortedClips,
    in: clipsDirectory(),
    musicURL: musicURL
)
```

- [ ] **Step 7: Remove unused functions**

Delete the `rotateClip(_ clip:)` private function entirely (the one that did `clip.rotationOverride = (clip.rotationOverride + 270) % 360`).

Delete the `importMusic(from:)` private function entirely (it now lives in `MusicPickerSheet`).

Delete the `removeMusic()` private function entirely.

- [ ] **Step 8: Build the project**

Build in Xcode (⌘B). Expected: clean build with no errors.

- [ ] **Step 9: Commit**

```bash
git add vidajary/vidajary/Views/Preview/PreviewView.swift
git commit -m "feat: wire up ClipEditView, MusicPickerSheet, and simplified bottom bar in PreviewView"
```

---

## Task 6: Delete ClipTrimView and clean up

**Files:**
- Delete: `vidajary/vidajary/Views/Preview/ClipTrimView.swift`

- [ ] **Step 1: Delete the file**

```bash
rm vidajary/vidajary/Views/Preview/ClipTrimView.swift
```

Also remove it from the Xcode project: in Xcode's Project Navigator, right-click `ClipTrimView.swift` → Delete → Move to Trash.

- [ ] **Step 2: Build the project**

Build in Xcode (⌘B). Expected: clean build — nothing references `ClipTrimView` anymore.

- [ ] **Step 3: Run all tests**

Run `vidajaryTests` in Xcode. Expected: all tests pass including the new `testClipVolumeDefaults` and `testClipVolumesPersist`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: remove ClipTrimView now that ClipEditView covers all clip editing"
```
