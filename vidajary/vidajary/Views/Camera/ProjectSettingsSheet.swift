import SwiftUI
import SwiftData

struct ProjectSettingsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var project: Project
    var onDeleted: (() -> Void)?

    @State private var name = ""
    @State private var showDeleteConfirm = false

    @State private var isExporting = false
    @State private var archiveURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var showDeleteAfterExport = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Name") {
                    TextField("Name", text: $name)
                }
                Section {
                    Toggle("Save clips to Photos", isOn: Bindable(project).saveClipsToLibrary)
                }

                Section("Archive") {
                    if isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Creating archive…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Export Archive") {
                            startExport(thenDelete: false)
                        }
                        Button("Archive & Delete") {
                            startExport(thenDelete: true)
                        }
                        .foregroundStyle(.orange)
                    }
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
                    deleteProject()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All clips will be permanently deleted.")
            }
            .confirmationDialog(
                "Free Up Space?",
                isPresented: $showDeleteAfterExport,
                titleVisibility: .visible
            ) {
                Button("Delete from Device", role: .destructive) {
                    deleteProject()
                }
                Button("Keep on Device", role: .cancel) {}
            } message: {
                Text("Archive saved. Delete this project from your device to free up storage?")
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = archiveURL {
                    ShareSheet(items: [url]) { completed in
                        if completed && showDeleteAfterExportPending {
                            showDeleteAfterExport = true
                        }
                        showDeleteAfterExportPending = false
                    }
                }
            }
        }
    }

    @State private var showDeleteAfterExportPending = false

    private func startExport(thenDelete: Bool) {
        showDeleteAfterExportPending = thenDelete
        isExporting = true
        Task {
            defer { isExporting = false }
            let safeName = project.name
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "-")
            let filename = safeName.isEmpty ? "archive" : safeName
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(filename).vidajary")
            do {
                try ArchiveService.export(project: project, to: tempURL)
                archiveURL = tempURL
                showShareSheet = true
            } catch {
                exportError = error.localizedDescription
                showDeleteAfterExportPending = false
            }
        }
    }

    private func deleteProject() {
        let dir = clipsDirectory()
        for clip in project.clips {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(clip.filename))
        }
        if let music = project.musicFilename {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(music))
        }
        context.delete(project)
        try? context.save()
        dismiss()
        onDeleted?()
    }
}

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
