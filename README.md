# **Coloring**
### *An iPad-first coloring studio with Apple Pencil-native drawing and resilient iCloud recovery.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-PencilKit-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-iPadOS-blue">
  <img src="https://img.shields.io/badge/Templates-39%20Built--In-purple">
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
| **Resizable Library Sidebar** | Drag the sidebar edge to tune library width; preferred width is remembered per scene. |
| **39 Built-In Orientation Packs** | Includes 22 landscape and 17 portrait built-in drawings. |
| **In Progress Smart Folder** | A built-in folder automatically tracks drawings with saved strokes or fills and shows a live count badge. |
| **Favorites, Recent, and Completed Folders** | Pin favorite drawings, jump back into recently opened work, and mark drawings as finished with built-in sidebar folders. |
| **Expanded Built-In Folders** | Adds five title-based folders (Cities & Landmarks, Nature & Outdoors, People & Portraits, Animals & Wildlife, Action & Motion); drawings can appear in multiple folders. |
| **Folder Drag Reordering** | Reorder built-in and custom folders from Manage Categories using drag and drop. |
| **Import from Photos or Files** | Bring in custom outlines and color them in the same studio. |
| **Native PencilKit Controls** | Apple-native pen, marker, eraser, and color interactions. |
| **Apple Pencil Gesture Support** | Squeeze for eraser and double-tap to open tool/color picker. |
| **Fill Mode with Region Targeting** | Tap-to-fill uses normalized hit mapping so fills land in the tapped region across zoom levels. |
| **Fill Erasing in Coloring Mode** | The PencilKit eraser can remove touched fill regions after you switch back from fill mode. |
| **Unified Undo / Redo** | Toolbar undo and redo work across drawing strokes, fills, fill erasing, clears, and layer changes for the selected drawing. |
| **Layer Stack Workflow** | Open layer controls from the sidebar to manage layered drawing composition. |
| **Template Orientation Enforcement** | Landscape templates request landscape mode; portrait templates request portrait mode when opened. |
| **Native Zoom and Pan** | Pinch-to-zoom and natural navigation for close coloring detail. |
| **Stable Sidebar Scrolling** | Sidebar vertical bounce is disabled and the last scroll position is restored after collapsing/reopening the library. |
| **Adaptive Floating Palette** | Palette can be moved between top and bottom, hides during active stroke interaction, and returns shortly after drawing stops. |
| **Liquid-Glass Gallery** | Exported artwork appears in a light, airy carousel with larger full-card previews and a translucent filmstrip navigator. |
| **PNG Export + Share** | Export template and stroke composite as a share-ready PNG. |
| **Imported Template iCloud Recovery** | Imported images are mirrored to iCloud and restored when local files are missing. |
| **Per-Template Progress Recovery** | Pencil strokes, fills, and layer state are restored per template so work reappears when you return. |
| **Destructive Action Confirmations** | Confirmation prompts for clear strokes, clear fills, and imported drawing deletions. |
| **Template Name/Image Stability** | Built-in titles remain aligned to their correct artwork assets. |

---

## Controls

- **Template Selection**: Choose any built-in or imported template from the sidebar.
- **Category Folders**: Use built-in filters including `In Progress` (with a live count badge), `Favorites`, `Recent`, `Completed`, plus the five title-based folders; the same drawing may appear in more than one built-in folder.
- **Folder Ordering**: Open **Manage Categories** and drag folders to set the order shown in category chips.
- **Favorites / Completed**: Long-press a drawing in the sidebar to favorite it or mark it completed.
- **Recent**: The `Recent` folder shows the most recently opened drawings first.
- **Orientation by Template**: Built-in landscape drawings open in landscape mode; built-in portrait drawings open in portrait mode.
- **Sidebar Updates**: Library refreshes automatically after launch, foreground, and import/delete actions (no manual pull-to-refresh).
- **Sidebar Resize**: Drag the sidebar's trailing handle to set your preferred library width.
- **Sidebar Status Messages**: Import/export and restore messages are shown inline without a separate "Status" section title.
- **Coloring**: Draw directly with PencilKit tools and Apple Pencil gestures.
- **Zoom and Pan**: Pinch to zoom and move around the canvas naturally.
- **Initial Fit Centering**: New templates open centered at fit scale, including portrait drawings on landscape iPad screens.
- **Fill**: Switch to fill mode from the floating palette and tap enclosed regions to color them.
- **Palette Position**: Use the arrow button in the palette to move it between top and bottom.
- **Undo/Redo**: Use the toolbar arrows in draw mode or fill mode to step backward or forward through recent edits for the selected drawing.
- **Fill Erasing**: After filling, switch back to coloring mode and use the PencilKit eraser to remove the touched fill region.
- **Layers**: Open **Layers** from the sidebar to manage stacked drawing content.
- **Import**: Add templates from Photos or Files.
- **Manage Imported Templates**: Rename, delete one, or use **Delete All Imported** (with confirmations).
- **Clear Actions**: Clear strokes and clear fills are both confirmation-protected.
- **Export**: Create a PNG and share from the system share sheet.
- **Gallery Navigation**: Switch between Studio and Gallery using the top segmented pill without a duplicate Gallery header in the content area.

---

## How it works

Coloring follows a predictable persistence and rendering pipeline:

1. Load built-in templates from bundled manifest/resources.
2. Load imported template metadata from local storage.
3. Attempt imported template recovery from iCloud when local files are unavailable.
4. Restore saved folder state (favorites, completed, recent order) for available templates.
5. Load selected template image into the studio.
6. Convert fill taps into normalized image-space points and apply flood-fill updates to the active template overlay.
7. Persist drawing, fill, and layer-stack updates per template locally.
8. Mirror drawing/fill/imported-template data to iCloud when available.
9. Restore drawing/fill/layer state for the selected template on reload/reinstall.
10. Export template image + fills + layer composites + active strokes into a composited PNG.

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

### **FloodFillService**
- Performs region flood-fill operations for fill mode.
- Works with normalized tap mapping from the canvas bridge to maintain accurate fill placement.

### **LayerCompositorService**
- Composites visible layers into export-ready bitmaps.
- Supports layered drawing workflows from the sidebar layer panel.

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

- [ ] Search by drawing title.
- [ ] Custom color palettes or recent colors.
- [ ] Additional automated test coverage and reduced simulator flakiness.

---

## Credits

Built with care by **Don Noel** and AI collaboration.

---

> *Coloring is designed to keep the drawing experience simple, focused, and recoverable across app reinstalls.*
