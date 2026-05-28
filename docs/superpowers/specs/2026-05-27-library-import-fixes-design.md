# Library Import Fixes

## Goal

Two fixes to the library import flow: show a loading indicator while videos are being processed, and ensure imported clips are ordered chronologically by capture time.

## Issue 1 — Loading State

### Problem

`LibraryPickerView.Coordinator` calls `onDismissed()` immediately when the picker finishes, then loads videos asynchronously in a background `Task`. The sheet closes and the user sees nothing happening until all clips suddenly appear.

### Design

**`LibraryPickerView`:** Add an `onImportStarted: () -> Void` callback. Fire it (on the main queue) only when `results.isEmpty == false`, immediately after `onDismissed`. This signals to the caller that a load is in progress.

```swift
// In picker(_:didFinishPicking:):
DispatchQueue.main.async { self.onDismissed() }
guard !results.isEmpty else { return }
DispatchQueue.main.async { self.onImportStarted() }  // new
Task { ... }
```

**`PreviewView`:** Add `@State private var isImporting = false`. In the `LibraryPickerView` sheet:
- Set `isImporting = true` in `onImportStarted`
- Set `isImporting = false` at the end of `onPicked` (after `rebuildPlayer` is dispatched)

**List area:** Add `isImporting` as the first branch in the list area conditional:

```swift
if isImporting {
    VStack(spacing: 12) {
        ProgressView().tint(.white)
        Text("Importing videos…")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
} else if sortedClips.isEmpty {
    // existing empty state
} else {
    // existing ScrollViewReader list
}
```

## Issue 2 — Import Order

### Problem

Clips arrive in the order the user tapped them in the picker (or the order `loadVideo` completed). The `sortOrder` assigned in `onPicked` reflects this arbitrary order rather than capture time.

### Design

In `onPicked` in `PreviewView`, sort the incoming `clips` array by `creationDate` (the `Date` element, index 2) before iterating:

```swift
let sorted = clips.sorted { $0.2 < $1.2 }
let baseOrder = project.clips.count
for (i, (url, duration, creationDate)) in sorted.enumerated() {
    let clip = Clip(filename: url.lastPathComponent, duration: duration,
                   sortOrder: baseOrder + i, recordedAt: creationDate)
    project.clips.append(clip)
}
```

This sorts only the newly imported batch. Existing clips in the project are not re-ordered.

## Out of Scope

- Re-sorting existing clips when new ones are imported
- Progress per-clip (e.g. "3 of 10") — a simple spinner is sufficient
- Loading state in `CameraView` (it does not use `LibraryPickerView`)
