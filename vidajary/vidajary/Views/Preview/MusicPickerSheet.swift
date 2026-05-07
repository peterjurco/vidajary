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
