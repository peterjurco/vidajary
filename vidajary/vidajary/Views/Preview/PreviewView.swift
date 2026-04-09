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

    var sortedClips: [Clip] {
        project.clips.sorted { $0.recordedAt < $1.recordedAt }
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
                }
                .padding(.horizontal, 12)

                if let player {
                    VideoPlayer(player: player)
                        .frame(maxHeight: .infinity)
                } else {
                    ProgressView().tint(.white).frame(maxHeight: .infinity)
                }

                // Clip list with swipe-to-delete
                List {
                    ForEach(sortedClips) { clip in
                        HStack {
                            Image(systemName: "video.fill").foregroundStyle(.secondary)
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .frame(maxHeight: 200)

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
        .task { await rebuildPlayer() }
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
    }

    private func rebuildPlayer() async {
        do {
            let composition = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory()
            )
            player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportVideo() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let composition = try await CompositionService.buildComposition(
                from: sortedClips,
                in: clipsDirectory()
            )
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try await ExportService.export(composition: composition, to: tmp)
            try await ExportService.saveToPhotoLibrary(url: tmp)
            try? FileManager.default.removeItem(at: tmp)
            showExportSuccess = true
        } catch {
            exportError = error.localizedDescription
        }
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
}
