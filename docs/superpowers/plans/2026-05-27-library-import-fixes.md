# Library Import Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two bugs in the library import flow: clips importing in wrong order, and no loading feedback while videos are being processed.

**Architecture:** Task 1 sorts the incoming clips batch by creation date before assigning sort orders — a one-line change in the `onPicked` callback in `PreviewView`. Task 2 adds an `onImportStarted` callback to `LibraryPickerView` so `PreviewView` can show a spinner in the list area while the async load is in progress.

**Tech Stack:** SwiftUI, PhotosUI (`PHPickerViewController`)

---

### Task 1: Fix import ordering

**Files:**
- Modify: `vidajary/vidajary/Views/Preview/PreviewView.swift:280-290`

- [ ] **Step 1: Replace the `onPicked` loop with a sorted version**

Find the `.sheet(isPresented: $showLibraryPicker)` block (lines 279–291). Replace the current `LibraryPickerView` call:

```swift
// BEFORE
.sheet(isPresented: $showLibraryPicker) {
    LibraryPickerView { clips in
        for (url, duration, creationDate) in clips {
            let clip = Clip(filename: url.lastPathComponent, duration: duration, sortOrder: project.clips.count, recordedAt: creationDate)
            project.clips.append(clip)
        }
        project.lastRecordedAt = Date()
        try? context.save()
        Task { await rebuildPlayer() }
    } onDismissed: {
        showLibraryPicker = false
    }
}
```

```swift
// AFTER
.sheet(isPresented: $showLibraryPicker) {
    LibraryPickerView { clips in
        let sorted = clips.sorted { $0.2 < $1.2 }
        let baseOrder = project.clips.count
        for (i, (url, duration, creationDate)) in sorted.enumerated() {
            let clip = Clip(filename: url.lastPathComponent, duration: duration, sortOrder: baseOrder + i, recordedAt: creationDate)
            project.clips.append(clip)
        }
        project.lastRecordedAt = Date()
        try? context.save()
        Task { await rebuildPlayer() }
    } onDismissed: {
        showLibraryPicker = false
    }
}
```

The only changes are: `let sorted = clips.sorted { $0.2 < $1.2 }`, iterating `sorted` instead of `clips`, and using `baseOrder + i` instead of `project.clips.count` for sort order.

- [ ] **Step 2: Verify the file compiles**

Check the edit looks syntactically correct — braces balanced, no stray characters.

- [ ] **Step 3: Commit**

```bash
git add vidajary/vidajary/Views/Preview/PreviewView.swift
git commit -m "fix: sort imported clips by capture date"
```

---

### Task 2: Loading state during import

**Files:**
- Modify: `vidajary/vidajary/Views/Camera/LibraryPickerView.swift`
- Modify: `vidajary/vidajary/Views/Preview/PreviewView.swift`

#### Part A — Add `onImportStarted` callback to `LibraryPickerView`

- [ ] **Step 1: Add the callback property and thread it through**

Replace the entire contents of `LibraryPickerView.swift` with:

```swift
import SwiftUI
import PhotosUI
import AVFoundation

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPicked: ([(URL, TimeInterval, Date)]) -> Void
    var onImportStarted: () -> Void
    var onDismissed: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onImportStarted: onImportStarted, onDismissed: onDismissed) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([(URL, TimeInterval, Date)]) -> Void
        let onImportStarted: () -> Void
        let onDismissed: () -> Void

        init(onPicked: @escaping ([(URL, TimeInterval, Date)]) -> Void,
             onImportStarted: @escaping () -> Void,
             onDismissed: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onImportStarted = onImportStarted
            self.onDismissed = onDismissed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            DispatchQueue.main.async { self.onDismissed() }
            guard !results.isEmpty else { return }
            DispatchQueue.main.async { self.onImportStarted() }
            Task {
                var clips: [(URL, TimeInterval, Date)] = []
                for result in results {
                    if let clip = await Self.loadVideo(from: result) {
                        clips.append(clip)
                    }
                }
                if !clips.isEmpty {
                    await MainActor.run { self.onPicked(clips) }
                }
            }
        }

        private static func loadVideo(from result: PHPickerResult) async -> (URL, TimeInterval, Date)? {
            let creationDate: Date = {
                guard let identifier = result.assetIdentifier else { return Date() }
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                return assets.firstObject?.creationDate ?? Date()
            }()

            return await withCheckedContinuation { continuation in
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                    guard let url, error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let destination = newClipURL()
                    do {
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch {
                        continuation.resume(returning: nil)
                        return
                    }
                    Task {
                        do {
                            let asset = AVURLAsset(url: destination)
                            let duration = try await asset.load(.duration)
                            continuation.resume(returning: (destination, duration.seconds, creationDate))
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
}
```

The only changes from the original are: `onImportStarted` property, threaded through `makeCoordinator` and `Coordinator.init`, and the `DispatchQueue.main.async { self.onImportStarted() }` line in `picker(_:didFinishPicking:)`.

#### Part B — Wire `isImporting` state in `PreviewView`

- [ ] **Step 2: Add the `isImporting` state variable**

In `PreviewView.swift`, find the `@State` declarations block (lines 11–26). Add after `@State private var isRebuildingPlayer = false`:

```swift
@State private var isImporting = false
```

- [ ] **Step 3: Add the loading branch to the list area**

Find the list area conditional (starts with `// Clip list with swipe-to-delete`). Currently:

```swift
// Clip list with swipe-to-delete
if sortedClips.isEmpty {
```

Replace with:

```swift
// Clip list with swipe-to-delete
if isImporting {
    VStack(spacing: 12) {
        ProgressView().tint(.white)
        Text("Importing videos…")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
} else if sortedClips.isEmpty {
```

No other changes to the list area.

- [ ] **Step 4: Wire `onImportStarted` and set `isImporting = false` in the sheet**

Find the `.sheet(isPresented: $showLibraryPicker)` block (which after Task 1 now uses `sorted`). Replace it:

```swift
.sheet(isPresented: $showLibraryPicker) {
    LibraryPickerView { clips in
        let sorted = clips.sorted { $0.2 < $1.2 }
        let baseOrder = project.clips.count
        for (i, (url, duration, creationDate)) in sorted.enumerated() {
            let clip = Clip(filename: url.lastPathComponent, duration: duration, sortOrder: baseOrder + i, recordedAt: creationDate)
            project.clips.append(clip)
        }
        project.lastRecordedAt = Date()
        try? context.save()
        isImporting = false
        Task { await rebuildPlayer() }
    } onImportStarted: {
        isImporting = true
    } onDismissed: {
        showLibraryPicker = false
    }
}
```

The changes from Task 1's version: `isImporting = false` added before `Task { await rebuildPlayer() }`, and the new `onImportStarted` trailing closure.

- [ ] **Step 5: Verify the file compiles**

Check both files for balanced braces and correct parameter labels.

- [ ] **Step 6: Commit**

```bash
git add vidajary/vidajary/Views/Camera/LibraryPickerView.swift
git add vidajary/vidajary/Views/Preview/PreviewView.swift
git commit -m "feat: show loading indicator while importing videos from library"
```
