# Vidajary

An iPhone video diary app. Record clips across multiple projects, preview them stitched together, and export to your photo library.

## Features

- **Projects** — organise clips into named projects
- **Camera** — full-screen recording with pinch-to-zoom (including ultrawide 0.5×), front/back camera flip, and correct orientation metadata for portrait and landscape
- **Preview** — plays all clips in a project stitched together in the correct orientation; swipe-to-delete individual clips; import clips from your photo library
- **Export** — renders the composition and saves it to Photos
- **Auto-save** — optionally save each clip to the photo library immediately after recording

## Requirements

- iPhone running iOS 17.6+
- Xcode 15+
- Apple Developer account (free account works for personal use; paid $99/year required for App Store or TestFlight distribution)

## Setup

1. Clone the repo
2. Open `vidajary/vidajary.xcodeproj` in Xcode
3. Select your development team in the project's Signing & Capabilities tab
4. Connect your iPhone and hit **Cmd+R**

No external dependencies — pure Swift, SwiftUI, SwiftData, and AVFoundation.

## Project Structure

```
vidajary/
├── Models/
│   ├── Project.swift          SwiftData model for a project
│   └── Clip.swift             SwiftData model for a single recorded clip
├── Services/
│   ├── CameraService.swift    AVCaptureSession setup, recording, zoom
│   ├── CompositionService.swift  Stitches clips into AVMutableComposition with rotation
│   ├── ExportService.swift    Renders composition and saves to Photos
│   └── FileStorage.swift      Resolves the clips directory in app support
├── Views/
│   ├── Camera/
│   │   ├── CameraView.swift         Main recording screen
│   │   ├── CameraPreviewView.swift  AVCaptureSession preview layer
│   │   └── LibraryPickerView.swift  PHPicker for importing library clips
│   ├── Preview/
│   │   └── PreviewView.swift        Playback, clip list, export
│   └── Projects/
│       ├── ProjectsView.swift       Project list with thumbnails
│       ├── NewProjectSheet.swift    Create project sheet
│       └── ProjectSettingsSheet.swift  Rename / delete project
├── AppDelegate.swift          Dynamic per-screen orientation control
├── ContentView.swift          Root navigation between camera and projects
└── vidajaryApp.swift          App entry point with SwiftData container
```
