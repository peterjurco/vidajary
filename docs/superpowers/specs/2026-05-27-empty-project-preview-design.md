# Empty Project Preview Screen

## Goal

Allow navigating to the preview screen for projects that have no clips, so users can add videos from the photo library without first having to record something.

## Changes

### 1. `ProjectsView` — unlock preview for empty projects

Remove `.disabled(project.clips.isEmpty)` from the play/preview button. This is the only gate blocking navigation.

No change needed to the thumbnail area — it already only renders when a project has clips.

### 2. `PreviewView` — empty state

When `sortedClips.isEmpty`:

- **Clip list area:** Replace the `ForEach` list with a centred empty state containing:
  - A film-reel system icon (muted)
  - "No clips yet" title
  - "Add videos from your library to get started" subtitle
  - A tappable "Add from Library" button that sets `showLibraryPicker = true`
- **Video area:** Suppress the play button overlay (no clips to play).
- **`.task` on appear:** Skip `rebuildPlayer` when clips are empty — `CompositionService` handles it safely but there's no value in building an empty player.

The export button is already `disabled` when `sortedClips.isEmpty` — no change needed there.

## Out of scope

- Adding from library via the camera screen (separate flow)
- Any changes to how clips are recorded or saved
