import SwiftUI
import SwiftData
import AVFoundation

struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Binding var activeProject: Project?
    @State private var showNewProject = false
    @State private var projectForSettings: Project? = nil
    @State private var projectThumbnails: [UUID: UIImage] = [:]
    @State private var projectForPreview: Project? = nil
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    HStack {
                        // Thumbnail
                        if let thumbnail = projectThumbnails[project.id] {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 40)
                                .clipped()
                                .cornerRadius(4)
                        } else if !project.clips.isEmpty {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 56, height: 40)
                        }

                        Button {
                            activeProject = project
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(project.clips.count) clips · \(formattedDuration(project.totalDuration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            projectForPreview = project
                        } label: {
                            Image(systemName: "play.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(project.clips.isEmpty)

                        Button {
                            projectForSettings = project
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete(perform: deleteProjects)
            }
            .task {
                await loadThumbnails()
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewProject = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectSheet { project in
                    activeProject = project
                }
            }
            .sheet(item: $projectForSettings) { project in
                ProjectSettingsSheet(project: project, onDeleted: {
                    if activeProject?.id == project.id {
                        activeProject = nil
                    }
                    projectForSettings = nil
                })
            }
            .fullScreenCover(item: $projectForPreview) { project in
                PreviewView(project: project)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try ArchiveService.importArchive(from: url, context: context)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
            .alert("Import Failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        let dir = clipsDirectory()
        for index in offsets {
            let project = projects[index]
            for clip in project.clips {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(clip.filename))
            }
            context.delete(project)
        }
    }

    private func loadThumbnails() async {
        let dir = clipsDirectory()
        for project in projects {
            guard let firstClip = project.clips.min(by: { $0.recordedAt < $1.recordedAt }) else { continue }
            let url = dir.appendingPathComponent(firstClip.filename)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 80)
            do {
                let (cgImage, _) = try await generator.image(at: .zero)
                projectThumbnails[project.id] = UIImage(cgImage: cgImage)
            } catch {
                // No thumbnail for this project
            }
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
