import SwiftUI
import SwiftData

struct ProjectSettingsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var project: Project
    var onDeleted: (() -> Void)?

    @State private var name = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Name") {
                    TextField("Name", text: $name)
                }
                Section {
                    Toggle("Save clips to Photos", isOn: Bindable(project).saveClipsToLibrary)
                }
                Section {
                    Button("Delete Project", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !name.isEmpty { project.name = name }
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear { name = project.name }
            .confirmationDialog(
                "Delete \"\(project.name)\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Project", role: .destructive) {
                    let dir = clipsDirectory()
                    for clip in project.clips {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(clip.filename))
                    }
                    context.delete(project)
                    try? context.save()
                    dismiss()
                    onDeleted?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All clips will be permanently deleted.")
            }
        }
    }
}
