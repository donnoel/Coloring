# Coloring

An iPad-first SwiftUI coloring studio focused on fullscreen templates, Apple Pencil-native drawing, and resilient local plus iCloud-backed recovery.

---

## What Is Coloring?

Coloring is built for a direct "open and color" flow:
- pick any template from one unified library,
- draw with native PencilKit controls,
- zoom and pan naturally for detail work,
- export as a composited PNG when done.

The app is intentionally offline-first, with iCloud used for backup/recovery of imported templates and per-template drawing progress.

---

## Core Features

| Feature | Description |
|---|---|
| Fullscreen Studio | Single immersive studio with no tab switching between scenes/templates. |
| Unified Library | Built-in and imported drawings appear in one sidebar list. |
| Built-In Templates | 20 included 4:3 line-art templates across scenery, racing, and fun themes. |
| Import From Photos/Files | Add custom outline drawings and manage them in-app. |
| Native PencilKit Tools | Apple-native pen/marker/eraser/color tool picker behavior. |
| Apple Pencil Gestures | Squeeze to switch eraser, double-tap to open tool/color picker. |
| Native Zoom + Pan | Pinch-to-zoom and natural canvas navigation for close detail coloring. |
| PNG Export + Share | Composites template and strokes into a shareable PNG file. |
| Imported Template iCloud Recovery | Imported templates are mirrored to iCloud and restored if local files are missing. |
| Per-Template Stroke Recovery | Drawing strokes are saved per template and mirrored to iCloud for reinstall recovery. |
| Safe Delete Flows | Single-delete and delete-all imported reset actions include confirmation dialogs. |
| Name/Image Mapping Stability | Built-in library loading keeps template names aligned to correct artwork assets. |

---

## Persistence and iCloud Behavior

Coloring uses an offline-first model with iCloud backup/restore:

- Imported templates are written locally with atomic writes.
- Imported templates are mirrored into iCloud Documents when available.
- Per-template drawing data is stored locally and mirrored to iCloud.
- On launch and foreground, missing local content can be restored from iCloud.
- iCloud placeholder files are handled to reduce failed restore cases.

This supports the recovery scenario:
1. Install app and color a template.
2. Delete app/build.
3. Reinstall app/build.
4. Reopen same template and recover prior work (after iCloud sync delay if needed).

---

## Architecture Overview

Coloring follows SwiftUI + MVVM with focused services:

- `Coloring/ViewModels/TemplateStudioViewModel.swift`
  - owns studio state, selection, drawing updates, import/export actions, and persistence orchestration.
- `Coloring/Services/TemplateLibraryService.swift`
  - owns built-in/imported template catalog, atomic import persistence, iCloud template sync/restore, and drawing-data store services.
- `Coloring/Services/TemplateArtworkExportService.swift`
  - composites selected template image with `PKDrawing` and writes export PNG.
- `Coloring/Views/TemplateStudioView.swift`
  - main iPad studio shell, sidebar management actions, and confirmation-driven destructive actions.
- `Coloring/Views/PencilCanvasView.swift`
  - PencilKit canvas bridge, native tool picker, and zoom/pan behavior.
- `ColoringTests/ColoringTests.swift`
  - view-model and template flow coverage, including persistence/reload behavior.

---

## Project Structure

```text
Coloring/
├── Coloring/
│   ├── Models/
│   ├── Resources/
│   │   └── Templates/
│   ├── Services/
│   ├── ViewModels/
│   └── Views/
├── ColoringTests/
├── ColoringUITests/
└── Coloring.xcodeproj
```

---

## Getting Started

### Requirements
- Xcode 17+
- iOS/iPad simulator runtime

### Run
1. Open `/Users/donnoel/Development/Coloring/Coloring.xcodeproj`.
2. Select scheme `Coloring`.
3. Choose an iPad destination (simulator or device).
4. Build and run.

---

## Build and Test

Clean build:

```bash
xcodebuild -project Coloring.xcodeproj -scheme Coloring -destination 'generic/platform=iOS Simulator' clean build
```

Run full tests:

```bash
xcodebuild -project Coloring.xcodeproj -scheme Coloring -destination 'platform=iOS Simulator,name=iPad (A16)' test
```

---

## Troubleshooting

- If imported templates or drawings do not appear immediately after reinstall:
  - verify same iCloud account and iCloud Drive enabled,
  - open app and wait briefly for iCloud hydration,
  - background/foreground app once to trigger deferred restore retry.
- If iCloud is unavailable, the app continues to work with local-only storage.
- If restore is still missing after several minutes, collect device logs for ubiquity container availability and restore errors.

---

## Near-Term Roadmap

- Template category filtering and favorites.
- Undo/redo workflow improvements.
- Broader automated coverage and lower simulator test flakiness.
