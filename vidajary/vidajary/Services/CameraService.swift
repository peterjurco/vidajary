import AVFoundation
import UIKit

@Observable
final class CameraService: NSObject {
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()
    var onClipRecorded: ((URL, TimeInterval) -> Void)?

    private var currentDeviceInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingStartTime: Date?

    enum CameraError: Error {
        case accessDenied
        case deviceUnavailable
    }

    func setup() async throws {
        guard !session.isRunning else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.accessDenied }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CameraError.accessDenied }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        try configureSession(position: .back)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }

        let videoDevice: AVCaptureDevice?
        if position == .back {
            videoDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        } else {
            videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        guard
            let videoDevice,
            let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
            session.canAddInput(videoInput)
        else { throw CameraError.deviceUnavailable }

        session.addInput(videoInput)
        currentDeviceInput = videoInput
        currentPosition = position

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
    }

    func startRecording(to url: URL) {
        guard !isRecording else { return }
        if let connection = movieOutput.connection(with: .video) {
            let angle: CGFloat
            switch UIDevice.current.orientation {
            case .landscapeLeft:        angle = 0
            case .landscapeRight:       angle = 180
            case .portraitUpsideDown:   angle = 270
            default:                    angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recordingStartTime = Date()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    func flipCamera() throws {
        let next: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        try configureSession(position: next)
    }

    func stopSession() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
        }
    }

    var minZoomFactor: CGFloat {
        currentDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.unlockForConfiguration()
        } catch {
            return
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        guard error == nil else {
            DispatchQueue.main.async { self.isRecording = false }
            return
        }
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        DispatchQueue.main.async {
            self.isRecording = false
            self.onClipRecorded?(outputFileURL, duration)
        }
    }
}
