import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var projects: [Project]
    @AppStorage("lastActiveProjectID") private var lastActiveProjectID: String = ""
    @State private var activeProject: Project?
    @State private var showProjects = false

    var body: some View {
        Group {
            if let project = activeProject {
                CameraView(project: project) {
                    showProjects = true
                }
                .sheet(isPresented: $showProjects) {
                    ProjectsView(activeProject: $activeProject)
                }
            } else {
                ProjectsView(activeProject: $activeProject)
            }
        }
        .onChange(of: activeProject) { _, newProject in
            lastActiveProjectID = newProject?.id.uuidString ?? ""
        }
        .onAppear {
            if activeProject == nil, !lastActiveProjectID.isEmpty {
                activeProject = projects.first { $0.id.uuidString == lastActiveProjectID }
            }
        }
    }
}
