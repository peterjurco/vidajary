import SwiftUI
import AVKit
import AVFoundation
import SwiftData

struct ClipTrimView: View {
    var clip: Clip
    let clipURL: URL

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var filmstrip: [UIImage] = []
    @State private var localTrimStart: TimeInterval
    @State private var localTrimEnd: TimeInterval
    @State private var isPlaying = false
    @State private var playerItem: AVPlayerItem?

    init(clip: Clip, clipURL: URL) {
        self.clip = clip
        self.clipURL = clipURL
        _localTrimStart = State(initialValue: clip.trimStart)
        _localTrimEnd = State(initialValue: min(clip.duration, clip.trimEnd > 0 ? clip.trimEnd : clip.duration))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Cancel") {
                        player?.pause()
                        dismiss()
                    }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(height: 44)
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
                    Button("Done") {
                        clip.trimStart = localTrimStart
                        clip.trimEnd = localTrimEnd
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

                // Filmstrip + handles
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Filmstrip
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

                        // Dimmed area before start handle
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

                        // Yellow border around selected region
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: 60)
                            .offset(x: startX)

                        // Start handle
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

                        // End handle
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
                .padding(.vertical, 16)
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
