import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var onCreated: (Project) -> Void

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let project = Project(name: name.isEmpty ? "Untitled" : name)
                        context.insert(project)
                        try? context.save()
                        onCreated(project)
                        dismiss()
                    }
                }
            }
        }
    }
}
