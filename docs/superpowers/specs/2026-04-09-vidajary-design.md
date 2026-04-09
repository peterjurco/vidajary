# Vidajary — Design Spec

**Date:** 2026-04-09
**Status:** Approved

---

## Context

Vidajary is an iPhone app for recording short video clips and accumulating them into a single continuous video — like a VHS camera. The user presses record, stops, and the clip is silently appended to the current project. No transitions, no editing, just a growing tape. The use case: vacation diaries, child milestones, road trips — moments from different times that belong in one video.

---

## Tech Stack

- **Platform:** iOS 17+, iPhone only
- **Language:** Swift
- **UI:** SwiftUI
- **Video:** AVFoundation (no third-party libraries)
- **Persistence:** SwiftData (metadata) + app sandbox filesystem (clip files)
- **Distribution:** App Store

---

## Data Model

```
Project
  id: UUID
  name: String
  createdAt: Date
  lastRecordedAt: Date?
  saveClipsToLibrary: Bool   // per-project toggle
  clips: [Clip]              // ordered

Clip
  id: UUID
  filename: String           // relative path within Documents/clips/
  recordedAt: Date
  duration: TimeInterval
```

Projects and their clip metadata are stored via SwiftData. Clip video files live in `Documents/clips/<uuid>.mov`. The `Documents/` directory is backed up by iCloud Backup but not synced across devices.

---

## Screens & Navigation

### App Launch Behavior
- **First launch:** Projects Screen
- **Subsequent launches:** Camera Screen, last active project pre-selected

### Projects Screen
- List of all projects, each row showing: name, clip count, total duration, last recorded date
- "+" button to create a new project (name entry → Camera Screen)
- Swipe to delete a project — confirmation alert — deletes metadata and all clip files on disk
- Tap a project → Camera Screen with that project active

### Camera Screen (main screen)
Full-screen `AVCaptureSession` preview with minimal cinematic overlay:

**Top bar:**
- Left: project name in uppercase spaced lettering — tap → Projects Screen
- Right: `⊕` (add from library) · `▶` (open Preview Screen)

**Bottom:**
- Flip camera button (left of record) · Record button (center)
- While recording: subtle REC indicator appears at top, no other UI changes

**Gestures:**
- Pinch on viewfinder → adjust `AVCaptureDevice.videoZoomFactor` (no discrete lens buttons)

**Behavior:**
- Tap record → start `AVCaptureMovieFileOutput` recording
- Tap again → stop recording → clip saved to `Documents/clips/<uuid>.mov` → appended to project's clip list → if `saveClipsToLibrary` is on, also saved to Photos library
- No confirmation, no preview — silently appended
- Tap flip → swap `AVCaptureDeviceInput` between front and back camera

**Project settings** (accessible via long-press on project name):
- Rename project
- Toggle: "Save clips to Photos"
- Delete project

### Preview Screen
- Full-screen `AVPlayer` playing an `AVMutableComposition` assembled from the project's clips in order
- Scrubber at bottom
- "Export to Library" button → `AVAssetExportSession` at source quality → saved to Photos via `PHPhotoLibrary`
- "✕" to dismiss back to Camera Screen

---

## Video Engine

| Task | AVFoundation API |
|------|-----------------|
| Live camera preview | `AVCaptureSession` + `AVCaptureVideoPreviewLayer` |
| Recording | `AVCaptureMovieFileOutput` |
| Flip camera | Swap `AVCaptureDeviceInput` (front ↔ back) |
| Pinch to zoom | `UIPinchGestureRecognizer` → `AVCaptureDevice.videoZoomFactor` |
| Preview playback | `AVMutableComposition` + `AVPlayer` in SwiftUI `VideoPlayer` |
| Export | `AVAssetExportSession` (highest quality preset matching source) |
| Add from library | `PHPickerViewController` → copy file into `Documents/clips/` |
| Save clip to Photos | `PHPhotoLibrary.shared().performChanges` |

No merging happens on disk until the user taps Export. The composition is assembled in-memory on demand.

---

## Permissions

| Permission | When requested |
|-----------|---------------|
| Camera | First launch |
| Microphone | First launch |
| Photo Library — add only | First export |
| Photo Library — read | First "add from library" |

---

## Clip Management

Individual clips can be deleted from within the Preview Screen (long-press or swipe on the scrubber/clip list). Deletion is permanent — removes the file from disk and updates the project metadata. No undo.

Clip reordering is out of scope for v1.

---

## Out of Scope (v1)

- iCloud sync across devices
- Clip reordering after recording
- Clip trimming
- Transitions between clips
- Multiple audio tracks
- Video quality selection at export
