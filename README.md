# **Coloring**
### *An iPad-first coloring studio with Apple Pencil-native drawing and resilient iCloud recovery.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-PencilKit-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-iPadOS-blue">
  <img src="https://img.shields.io/badge/Templates-80%20Built--In-purple">
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
| **Premium First-Run Onboarding** | A short 4-page visual onboarding introduces Studio, import/coloring controls, organization/sync behavior, and Gallery export/share flow on first launch. |
| **Unified Library Sidebar** | Built-in and imported templates shown together in one list. |
| **Resizable Library Sidebar** | Drag the sidebar edge to tune library width; preferred width is remembered per scene. |
| **80 Built-In Templates** | Manifest-driven built-ins across eight shelf categories with orientation metadata for filtering/layout. |
| **In Progress Smart Folder** | A built-in folder automatically tracks drawings with saved strokes or fills and shows a live count badge. |
| **Favorites, Recent, and Completed Folders** | Pin favorite drawings, jump back into recently opened work, and mark drawings as finished with built-in sidebar folders. |
| **Reversible Hidden Templates** | Long-press any built-in or imported drawing to hide it from normal browsing and recover it later from a dedicated `Hidden` management view. |
| **Expanded Built-In Folders** | Adds manifest-driven shelf folders (`Cozy`, `Nature`, `Animals`, `Fantasy`, `Patterns`, `Seasonal`, `Motorsport`, `Sci-Fi`), complexity folders (`Easy`, `Medium`, `Detailed`, `Dense`), and orientation folders (`Landscape`, `Portrait`) for built-in drawings. |
| **Folder Drag Reordering** | Reorder built-in and custom folders from Manage Categories using drag and drop. |
| **Import from Photos or Files** | Bring in custom outlines and color them in the same studio. |
| **Native PencilKit Controls** | Apple-native pen, marker, eraser, and color interactions. |
| **Apple Pencil Gesture Support** | Squeeze for eraser and double-tap to open tool/color picker. |
| **Fill Mode with Region Targeting** | Tap-to-fill uses normalized hit mapping so fills land in the tapped region across zoom levels, using the active PencilKit tool color. |
| **Fill Erasing in Coloring Mode** | The PencilKit eraser can remove touched fill regions after you switch back from fill mode. |
| **Unified Undo / Redo** | Toolbar undo and redo work across drawing strokes, fills, fill erasing, clears, and layer changes for the selected drawing. |
| **Layer Stack Workflow** | Open layer controls from the sidebar to manage layered drawing composition. |
| **Native Zoom and Pan** | Pinch-to-zoom and natural navigation for close coloring detail. |
| **Stable Sidebar Navigation** | Sidebar resize drag remains smooth while the chosen width persists across launches. |
| **Adaptive Floating Palette** | Palette can be moved between top and bottom, hides during active stroke interaction, and returns shortly after drawing stops. |
| **Unified Color Source** | Stroke and fill actions both use the active native PencilKit color selection. |
| **System Appearance Support** | Studio and gallery chrome adapt to light and dark mode while keeping the drawing canvas stable and the native PencilKit picker synchronized to current appearance. |
| **Liquid-Glass Gallery** | Exported artwork appears in a light, airy carousel with larger full-card previews and a translucent filmstrip navigator. |
| **High-Fidelity Gallery Stage** | The main gallery card uses full-resolution artwork while the bottom filmstrip uses lightweight thumbnails for quick scrolling. |
| **PNG Export + Share** | Export template and stroke composite as a share-ready PNG. |
| **Imported Template iCloud Recovery** | Imported images are mirrored to iCloud and restored when local files are missing. |
| **Per-Template Progress Recovery** | Pencil strokes, fills, and layer state are restored per template so work reappears when you return. |
| **Destructive Action Confirmations** | Confirmation prompts for clear strokes, clear fills, and imported drawing deletions. |
| **Template Name/Image Stability** | Built-in titles remain aligned to their correct artwork assets. |

---

## Controls

- **Template Selection**: Choose any built-in or imported template from the sidebar.
- **Category Folders**: Use built-in filters including `In Progress` (with a live count badge), `Favorites`, `Recent`, `Completed`, shelf folders (`Cozy`, `Nature`, `Animals`, `Fantasy`, `Patterns`, `Seasonal`, `Motorsport`, `Sci-Fi`), complexity folders (`Easy`, `Medium`, `Detailed`, `Dense`), and orientation folders (`Landscape`, `Portrait`); built-in drawings can appear in multiple metadata-driven folders.
- **Folder Ordering**: Open **Manage Categories** and drag folders to set the order shown in category chips.
- **Favorites / Completed / Hide**: Long-press a drawing in the sidebar to favorite it, mark it completed, or hide it.
- **Hidden Management**: Tap the `eye.slash` button in the Drawings header to open `Hidden`, where you can unhide individual drawings or use `Unhide All`.
- **Recent**: The `Recent` folder shows the most recently opened drawings first.
- **Sidebar Updates**: Library refreshes automatically after launch, foreground, and import/delete actions (no manual pull-to-refresh).
- **Sidebar Resize**: Drag the sidebar's trailing handle to set your preferred library width.
- **Sidebar Status Messages**: Import/export and restore messages are shown inline without a separate "Status" section title.
- **Coloring**: Draw directly with PencilKit tools and Apple Pencil gestures.
- **Zoom and Pan**: Pinch to zoom and move around the canvas naturally.
- **Initial Fit Centering**: New templates open centered at fit scale, including portrait drawings on landscape iPad screens.
- **Fill**: Switch to fill mode from the floating palette and tap enclosed regions to color them.
- **PencilKit Picker in Fill Mode**: The native PencilKit palette stays available in fill mode so you can change colors without switching back to draw mode.
- **Palette Position**: Use the arrow button in the palette to move it between top and bottom.
- **Undo/Redo**: Use the toolbar arrows in draw mode or fill mode to step backward or forward through recent edits for the selected drawing.
- **Fill Erasing**: After filling, switch back to coloring mode and use the PencilKit eraser to remove the touched fill region.
- **Fill Color Source**: Fill mode uses the currently selected PencilKit color, so strokes and fills share the same palette.
- **Layers**: Open **Layers** from the sidebar to manage stacked drawing content.
- **Import**: Add templates from Photos or Files.
- **Manage Imported Templates**: Rename, delete one, or use **Delete All Imported** (with confirmations).
- **Clear Actions**: Clear strokes and clear fills are both confirmation-protected.
- **Export**: Create a PNG and share from the system share sheet.
- **Gallery Navigation**: Switch between Studio and Gallery using the app’s tab navigation.
- **Gallery Fidelity**: Main carousel cards render full-resolution artwork; the thumbnail rail remains optimized for compact previews.
- **Light/Dark Mode**: App chrome follows the current system appearance automatically; drawing/export colors remain stable and gallery previews are white-backed so transparent regions do not darken in dark UI.

---

## How it works

Coloring follows a predictable persistence and rendering pipeline:

1. Load built-in templates from bundled manifest/resources.
2. Load imported template metadata from local storage.
3. Attempt imported template recovery from iCloud when local files are unavailable.
4. Restore saved folder state (favorites, completed, recent order, hidden template IDs) for available templates.
5. Filter hidden template IDs out of normal library browsing and metadata-driven built-in folder counts.
6. Load selected template image into the studio.
7. Convert fill taps into normalized image-space points and apply flood-fill updates to the active template overlay.
8. Persist drawing, fill, and layer-stack updates per template locally.
9. Mirror drawing/fill/imported-template data to iCloud when available.
10. Restore drawing/fill/layer state for the selected template on reload/reinstall.
11. Export template image + fills + layer composites + active strokes into a composited PNG.

---

## Architecture Overview

### **TemplateStudioViewModel (`@MainActor`)**
- Coordinates template selection, drawing state, import/export actions, and user-facing status messages.
- Triggers drawing persistence and restoration by template identifier.
- Applies hidden-template filtering before rendering normal library lists/categories.

### **TemplateLibraryService (actor)**
- Owns built-in/imported template catalog loading.
- Handles atomic imported template writes and iCloud mirror/restore behavior.

### **TemplateCategoryStoreService (actor)**
- Persists lightweight template library state such as favorites/completed/recent ordering and hidden template IDs.

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
