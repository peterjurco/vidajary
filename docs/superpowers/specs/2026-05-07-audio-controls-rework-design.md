# Audio Controls Rework — Design Spec

**Date:** 2026-05-07

## Overview

Rework audio controls to move all volume management into a per-clip editor, simplify the bottom bar to just the export button, and surface the background music picker from a top-toolbar icon.

---

## 1. Data Model

### Clip — new fields

```swift
var clipVolume: Float = 1.0      // This clip's audio volume (0.0–1.0)
var musicVolume: Float = 1.0     // Background music level during this clip (0.0–1.0)
```

Both fields get inline defaults so no SwiftData migration is needed.

### Project — no changes

`Project.videoVolume` and `Project.musicVolume` are kept as-is to avoid migration but are no longer used by `CompositionService` or any UI.

---

## 2. CompositionService

### Per-clip audio tracks

Replace the current single merged video audio track with one `AVMutableCompositionTrack` per clip. Each clip's audio track gets its own `AVMutableAudioMixInputParameters`:

```
setVolume(clip.clipVolume, at: clipStartTime)
```

### Music volume automation

Built by iterating clips in timeline order:

1. **First clip:** `setVolume(clips[0].musicVolume, at: .zero)` on the music track's parameters.
2. **Each subsequent clip:** if `clip.musicVolume != previousClip.musicVolume`, add:
   ```
   setVolumeRamp(
     fromStartVolume: previousClip.musicVolume,
     toEndVolume: clip.musicVolume,
     timeRange: CMTimeRange(start: boundaryTime, duration: 0.3s)
   )
   ```
   If `musicVolume` is the same as the previous clip, nothing is added (already at the correct level).

**Ramp duration:** 0.3 s. Applied starting at the clip boundary going into the new clip.

---

## 3. ClipEditView (new full-screen view)

Replaces both `ClipTrimView` and the per-clip rotate button. Presented via `.fullScreenCover`.

### Structure

- **Navigation bar:** Cancel | "Edit Clip" | Done
  - Done persists all changes to the model and dismisses
  - Cancel discards all local state and dismisses
- **Trim section:** existing filmstrip + drag handle UI from `ClipTrimView`, embedded inline
- **Rotation section:** a "Rotate" button that increments rotation by 270° (same logic as current rotate button). Displays the current angle as a text label next to the button.
- **Clip Volume section:** labeled slider, 0–100%, controls `clip.clipVolume`
- **Background Music section:** labeled slider, 0–100%, controls `clip.musicVolume`. Only shown when `project.musicFilename != nil`.

All edits are held in local `@State` until Done is tapped, matching the existing `ClipTrimView` pattern.

### ClipTrimView

Becomes unused and is deleted. Its filmstrip and drag handle logic is moved into `ClipEditView`.

---

## 4. PreviewView Changes

### Bottom bar

Remove entirely:
- Music picker row (Add Music button + remove X button)
- Video volume slider
- Music volume slider

Keep:
- Export button (unchanged)

### Top toolbar

Add a `music.note` icon button alongside the existing top-right icons. Tapping it presents `MusicPickerSheet` as a sheet.

### Per-clip row

Replace the rotate button (`rotate.left`) and scissors button (`scissors`) with a single pencil button (`pencil`). Tapping opens `ClipEditView` full-screen.

---

## 5. MusicPickerSheet (new view)

A small sheet presented from the top-toolbar music icon. Contains only:
- If no music: "Add Background Music" button (triggers the existing file importer)
- If music exists: filename label + "Remove" button

No volume controls here.

---

## Affected Files

| File | Change |
|------|--------|
| `Models/Clip.swift` | Add `clipVolume`, `musicVolume` fields |
| `Services/CompositionService.swift` | Per-clip audio tracks, music volume automation |
| `Views/Preview/PreviewView.swift` | Simplify bottom bar, add music icon, replace per-clip buttons |
| `Views/Preview/ClipTrimView.swift` | Delete — logic moves into ClipEditView |
| `Views/Preview/ClipEditView.swift` | New full-screen clip editor |
| `Views/Preview/MusicPickerSheet.swift` | New sheet for add/remove music |
