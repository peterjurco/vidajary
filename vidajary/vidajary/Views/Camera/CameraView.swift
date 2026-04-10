import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.modelContext) private var context
    var project: Project
    var onShowProjects: () -> Void
    var onProjectDeleted: () -> Void

    @State private var camera = CameraService()
    @State private var showPreview = false
    @State private var showSettings = false
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Full-screen camera preview
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            camera.setZoom(lastZoomScale * scale)
                        }
                        .onEnded { scale in
                            lastZoomScale = max(camera.minZoomFactor, min(lastZoomScale * scale, 10.0))
                        }
                )

            VStack {
                // Top bar
                HStack {
                    Text(project.name.uppercased())
                        .font(.system(size: 11, weight: .regular))
                        .kerning(3)
                        .foregroundStyle(.white.opacity(0.8))
                        .onLongPressGesture { showSettings = true }

                    Spacer()

                    HStack(spacing: 20) {
                        Button { onShowProjects() } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Button { showPreview = true } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .disabled(project.clips.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // REC indicator
                if camera.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("REC")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Bottom controls
                HStack(spacing: 40) {
                    Button {
                        try? camera.flipCamera()
                        lastZoomScale = 1.0
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(camera.isRecording)

                    // Record button
                    Button {
                        if camera.isRecording {
                            camera.stopRecording()
                        } else {
                            camera.startRecording(to: newClipURL())
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.4), lineWidth: 2)
                                .frame(width: 64, height: 64)
                            if camera.isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 50, height: 50)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: camera.isRecording)
                    }

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.bottom, 44)
            }
        }
        .task { await setupCamera() }
        .onDisappear {
            camera.stopSession()
        }
        .fullScreenCover(isPresented: $showPreview) {
            PreviewView(project: project)
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsSheet(project: project, onDeleted: onProjectDeleted)
        }
    }

    private func setupCamera() async {
        try? await camera.setup()
        camera.onClipRecorded = { url, duration in
            let clip = Clip(filename: url.lastPathComponent, duration: duration)
            project.clips.append(clip)
            project.lastRecordedAt = Date()
            try? context.save()
            if project.saveClipsToLibrary {
                Task { try? await ExportService.saveToPhotoLibrary(url: url) }
            }
        }
    }
}
