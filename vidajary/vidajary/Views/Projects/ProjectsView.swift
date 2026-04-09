import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Binding var activeProject: Project?
    @State private var showNewProject = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    Button {
                        activeProject = project
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
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteProjects)
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewProject = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectSheet { project in
                    activeProject = project
                }
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

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
