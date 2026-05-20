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
    @State private var exportResult: ExportResult? = nil

    enum ExportResult { case success, failure(String) }

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
                            startExport()
                        }
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
                Text("All clips will be permanently deleted. Export an archive first if you want to preserve this project.")
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
                    ShareSheet(items: [url]) { completed, error in
                        if let error {
                            exportResult = .failure(error.localizedDescription)
                        } else if completed {
                            exportResult = .success
                        }
                        // cancelled (completed == false, error == nil): no feedback
                    }
                    .onAppear { isExporting = false }
                }
            }
            .alert(
                exportResult == .success ? "Exported Successfully" : "Export Failed",
                isPresented: .init(get: { exportResult != nil }, set: { if !$0 { exportResult = nil } })
            ) {
                Button("OK") { exportResult = nil }
            } message: {
                if case .failure(let msg) = exportResult {
                    Text(msg)
                } else {
                    Text("The archive was saved successfully.")
                }
            }
        }
    }

    private func startExport() {
        isExporting = true
        Task {
            let safeName = project.name
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "-")
            let filename = safeName.isEmpty ? "archive" : safeName
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(filename).zip")
            do {
                try ArchiveService.export(project: project, to: tempURL)
                archiveURL = tempURL
                showShareSheet = true
                // isExporting cleared in sheet's onAppear to avoid gap before sheet presents
            } catch {
                isExporting = false
                exportError = error.localizedDescription
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
    var onComplete: (Bool, Error?) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, error in
            onComplete(completed, error)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
