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