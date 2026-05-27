# Empty Project Preview Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow opening the preview screen on an empty project so the user can add clips from the photo library.

**Architecture:** Two files change. `ProjectsView` drops the guard that disables the preview button. `PreviewView` gains an empty state (film icon + message + "Add from Library" button) that shows in place of the clip list, plus a guard in `rebuildPlayer` that clears the player and returns early when there are no clips.

**Tech Stack:** SwiftUI, AVFoundation, SwiftData

---

### Task 1: Unlock preview button for empty projects

**Files:**
- Modify: `vidajary/vidajary/Views/Projects/ProjectsView.swift:62`

- [ ] **Step 1: Remove the disabled modifier**

In `ProjectsView.swift`, find the play button (around line 54–62):

```swift
Button {
    projectForPreview = project
} label: {
    Image(systemName: "play.circle")
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
}
.buttonStyle(.plain)
.disabled(project.clips.isEmpty)   // ← delete this line
```

Remove the `.disabled(project.clips.isEmpty)` line so the button is always tappable.

- [ ] **Step 2: Build and verify the button is tappable on an empty project**

Run the app, create a new project without recording anything, and confirm the play button is no longer greyed out and tapping it opens the preview screen.

- [ ] **Step 3: Commit**

```bash
git add vidajary/vidajary/Views/Projects/ProjectsView.swift
git commit -m "feat: allow opening preview screen for empty projects"
```

---

### Task 2: Empty state in PreviewView

**Files:**
- Modify: `vidajary/vidajary/Views/Preview/PreviewView.swift`

- [ ] **Step 1: Guard `rebuildPlayer` against empty clips**

In `PreviewView.swift`, find `rebuildPlayer` (around line 263). Add an early-exit guard immediately after `stopTimeObserver()`:

```swift
private func rebuildPlayer() async {
    stopTimeObserver()
    guard !sortedClips.isEmpty else {
        player = nil
        clipRanges = []
        return
    }
    let preservedTime = pendingResumeTime ?? player?.currentTime()
    // … rest of function unchanged …
```

This ensures an empty project never creates a useless AVPlayer, and also handles the case where the user swipe-deletes all clips while inside the preview.

- [ ] **Step 2: Suppress the play overlay when there are no clips**

In the video area `ZStack`, change the condition on the play button overlay from:

```swift
} else if !isPlaying {
```

to:

```swift
} else if !isPlaying && !sortedClips.isEmpty {
```

Full context (lines 71–93):

```swift
if isRebuildingPlayer {
    Color.black.opacity(0.5).frame(height: 260)
    VStack(spacing: 10) {
        ProgressView().tint(.white)
        Text("Generating preview…")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
    }
} else if !isPlaying && !sortedClips.isEmpty {   // ← changed
    Button {
        player?.play()
        isPlaying = true
    } label: {
        ZStack {
            Circle()
                .fill(.black.opacity(0.4))
                .frame(width: 64, height: 64)
            Image(systemName: "play.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 3: Add empty state in place of the clip list**

The clip list starts at line 96 with `// Clip list with swipe-to-delete`. Wrap the existing `ScrollViewReader` block in an `if/else` so the empty state appears instead:

```swift
// Clip list with swipe-to-delete
if sortedClips.isEmpty {
    VStack(spacing: 16) {
        Image(systemName: "film")
            .font(.system(size: 40))
            .foregroundStyle(.white.opacity(0.25))
        VStack(spacing: 4) {
            Text("No clips yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add videos from your library to get started")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        Button {
            showLibraryPicker = true
        } label: {
            Label("Add from Library", systemImage: "plus.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
} else {
    ScrollViewReader { proxy in
        // … existing List { ForEach … } block unchanged …
    }
}
```

- [ ] **Step 4: Build and verify the full flow**

1. Open the app, create a new project, tap the play button — the preview screen opens showing the empty state (film icon + "No clips yet" + "Add from Library" button).
2. Tap "Add from Library" — the photo library picker opens.
3. Select a video — it appears in the clip list and the preview rebuilds.
4. Confirm the play button overlay now appears and playback works.
5. Swipe-delete all clips — the empty state reappears, the player clears.

- [ ] **Step 5: Commit**

```bash
git add vidajary/vidajary/Views/Preview/PreviewView.swift
git commit -m "feat: show empty state in preview screen when project has no clips"
```
