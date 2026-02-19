# **Coloring**
### *An iPad-first coloring studio with Apple Pencil-native drawing and resilient iCloud recovery.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-PencilKit-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-iPadOS-blue">
  <img src="https://img.shields.io/badge/Templates-20%20Built--In-purple">
  <img src="https://img.shields.io/badge/Sync-iCloud%20Documents-green?logo=icloud">
</p>

---

## What is Coloring?

**Coloring** is a fullscreen iPad coloring app designed around a direct workflow:

- choose a built-in or imported template,
- color with native PencilKit tools,
- zoom into detail work with natural gestures,
- export a composited PNG when finished.

The app is offline-first for day-to-day use and uses iCloud for recovery of imported templates and per-template drawing progress.

---

## Core Features

| Feature | Description |
|--------|-------------|
| **Single Fullscreen Studio** | No Scene/Templates tab split; one immersive coloring workspace. |
| **Unified Library Sidebar** | Built-in and imported templates shown together in one list. |
| **20 Built-In 4:3 Templates** | Included line-art packs for scenery, racing, and fun categories. |
| **Import from Photos or Files** | Bring in custom outlines and color them in the same studio. |
| **Native PencilKit Controls** | Apple-native pen, marker, eraser, and color interactions. |
| **Apple Pencil Gesture Support** | Squeeze for eraser and double-tap to open tool/color picker. |
| **Native Zoom and Pan** | Pinch-to-zoom and natural navigation for close coloring detail. |
| **PNG Export + Share** | Export template and stroke composite as a share-ready PNG. |
| **Imported Template iCloud Recovery** | Imported images are mirrored to iCloud and restored when local files are missing. |
| **Per-Template Stroke Recovery** | Drawing data is persisted per template and mirrored to iCloud for reinstall recovery. |
| **Last Open Drawing Restore** | The most recently selected template is reopened automatically on launch when still available. |
| **Orientation-Locked Strokes** | Pencil strokes stay aligned with template artwork when rotating between landscape and portrait. |
| **Delete Confirmations** | Confirmation prompts for single imported delete and delete-all imported actions. |
| **Template Name/Image Stability** | Built-in titles remain aligned to their correct artwork assets. |

---

## Controls

- **Template Selection**: Choose any built-in or imported template from the sidebar.
- **Coloring**: Draw directly with PencilKit tools and Apple Pencil gestures.
- **Zoom and Pan**: Pinch to zoom and move around the canvas naturally.
- **Import**: Add templates from Photos or Files.
- **Manage Imported Templates**: Rename, delete one, or delete all imported templates (with confirmations).
- **Export**: Create a PNG and share from the system share sheet.

---

## How it works

Coloring follows a predictable persistence and rendering pipeline:

1. Load built-in templates from bundled manifest/resources.
2. Load imported template metadata from local storage.
3. Attempt imported template recovery from iCloud when local files are unavailable.
4. Restore the last selected template ID and fall back safely if it no longer exists.
5. Load selected template image into the studio.
6. Persist drawing updates per template locally.
7. Mirror drawing data and imported templates to iCloud when available.
8. Restore drawing data for the selected template on reload/reinstall.
9. Export template image + drawing strokes into a composited PNG.

---

## Architecture Overview

### **TemplateStudioViewModel (`@MainActor`)**
- Coordinates template selection, drawing state, import/export actions, and user-facing status messages.
- Triggers drawing persistence and restoration by template identifier.

### **TemplateLibraryService (actor)**
- Owns built-in/imported template catalog loading.
- Handles atomic imported template writes and iCloud mirror/restore behavior.

### **TemplateDrawingStoreService (actor)**
- Owns per-template drawing persistence.
- Mirrors drawing data to iCloud Documents and restores when local data is missing.

### **TemplateArtworkExportService (actor)**
- Composites selected template bitmap + `PKDrawing` data.
- Writes deterministic PNG output for share/export.

### **UI Layer (SwiftUI + PencilKit bridge)**
- `TemplateStudioView` provides iPad-first library + studio shell.
- `PencilCanvasView` bridges PencilKit canvas, tool picker, and native gesture behavior.

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
- iPad simulator runtime (or physical iPad device)

### Setup
1. Open `/Users/donnoel/Development/Coloring/Coloring.xcodeproj`.
2. Select scheme `Coloring`.
3. Choose an iPad destination.
4. Build and run.

### Build
```bash
xcodebuild -project Coloring.xcodeproj -scheme Coloring -destination 'generic/platform=iOS Simulator' clean build
```

### Test
```bash
xcodebuild -project Coloring.xcodeproj -scheme Coloring -destination 'platform=iOS Simulator,name=iPad (A16)' test
```

---

## Notes and Conventions

- Persistence is **offline-first** with iCloud used for backup and recovery.
- Imported templates and drawing progress use atomic local writes where appropriate.
- If iCloud is unavailable, the app remains fully usable with local storage.
- Deferred restore retries are used to handle delayed iCloud availability at launch/foreground.

---

## Troubleshooting

- **Imported template missing after reinstall**
  - Confirm same Apple ID and iCloud Drive enabled on device.
  - Launch app and allow short hydration time.
  - Background/foreground once to trigger deferred retry.

- **Drawing progress not visible immediately**
  - Open the same template ID/title and wait for iCloud restore completion.
  - Verify iCloud container entitlement and account state on device.

- **Export failed**
  - Ensure a template is selected and retry export.
  - Check free disk space and share-sheet availability.

---

## Roadmap

- [ ] Template category filtering and favorites.
- [ ] Undo/redo workflow improvements.
- [ ] Additional automated test coverage and reduced simulator flakiness.

---

## Credits

Built with care by **Don Noel** and AI collaboration.

---

> *Coloring is designed to keep the drawing experience simple, focused, and recoverable across app reinstalls.*
