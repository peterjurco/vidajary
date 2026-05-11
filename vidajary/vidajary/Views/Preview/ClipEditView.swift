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
    @State private var clipAsset: AVURLAsset?

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
                            playerItem?.forwardPlaybackEndTime = CMTimeMakeWithSeconds(localTrimEnd, preferredTimescale: 600)
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
                        Slider(value: $localClipVolume, in: 0...2)
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
                            Slider(value: $localMusicVolume, in: 0...2)
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
            clipAsset = asset
            let item = AVPlayerItem(asset: asset)
            if let vc = await buildRotationComposition(asset: asset, rotation: localRotation) {
                item.videoComposition = vc
            }
            playerItem = item
            player = AVPlayer(playerItem: item)
            _ = await player?.seek(to: CMTimeMakeWithSeconds(localTrimStart, preferredTimescale: 600))
            await loadFilmstrip(asset: asset)
        }
        .onChange(of: localTrimEnd) { _, newEnd in
            playerItem?.forwardPlaybackEndTime = CMTimeMakeWithSeconds(newEnd, preferredTimescale: 600)
        }
        .onChange(of: localRotation) { _, newRotation in
            guard let asset = clipAsset else { return }
            Task {
                if let vc = await buildRotationComposition(asset: asset, rotation: newRotation) {
                    playerItem?.videoComposition = vc
                }
            }
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

    private func buildRotationComposition(asset: AVURLAsset, rotation: Int) async -> AVMutableVideoComposition? {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration),
              duration.seconds > 0 else { return nil }
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let frameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 30
        let renderSize = CompositionService.finalDisplaySize(
            naturalSize: naturalSize, transform: preferredTransform, rotationOverride: rotation)
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }
        let transform = CompositionService.fitTransform(
            naturalSize: naturalSize, preferredTransform: preferredTransform,
            rotationOverride: rotation, renderSize: renderSize)
        let vc = AVMutableVideoComposition()
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: max(1, Int32(frameRate.rounded())))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        vc.instructions = [instruction]
        return vc
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
