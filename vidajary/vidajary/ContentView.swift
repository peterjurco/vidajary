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
                CameraView(project: project, onShowProjects: {
                    showProjects = true
                }, onProjectDeleted: {
                    activeProject = nil
                })
                .fullScreenCover(isPresented: $showProjects) {
                    ProjectsView(activeProject: $activeProject)
                }
            } else {
                ProjectsView(activeProject: $activeProject)
            }
        }
        .onChange(of: activeProject) { _, newProject in
            lastActiveProjectID = newProject?.id.uuidString ?? ""
            if newProject != nil {
                showProjects = false
            }
        }
        .onAppear {
            if activeProject == nil, !lastActiveProjectID.isEmpty {
                activeProject = projects.first { $0.id.uuidString == lastActiveProjectID }
            }
        }
    }
}
