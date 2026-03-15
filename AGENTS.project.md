# AGENTS.project.md

# Coloring Project Guide for Agents

## Product intent
Coloring serves kids, families, and hobbyists who want a relaxing iPad coloring experience.
The app solves the need for ready-to-color, scene-based line art with a modern interface.
Success means users can pick a scene, color it intuitively, and export finished artwork quickly.

## Current product phase (MVP+ implemented)
1) MVP scope
- Single full-screen Apple Pencil studio (no Scene/Templates tab split)
- Unified sidebar list containing built-in and imported drawings
- PNG export + share flow
- Apple Pencil Template Studio with orientation-aware built-in packs (54 landscape + 18 portrait)
- Built-in folder filters include In Progress (with a live count badge), Favorites, Recent, Completed, Landscape/Portrait, three difficulty folders (Easy/Intermediate/Challenging), plus five title-based folders with multi-folder membership support
- Folder order is user-reorderable via drag-and-drop in Manage Categories and persists locally
- Imported drawing templates from Photos/Files
- Immersive template workflow: always-full-screen canvas first, native PencilKit picker, native UIScrollView pan/zoom navigation, and sidebar-managed import/export/clear/rename/delete controls

2) Architecture boundaries
- SwiftUI views handle presentation and interaction only
- View model owns screen state and user actions
- Services own scene catalog and export IO
- Services own template catalog/import persistence and template export IO

3) Reliability and UX goals
- Clean build with no warnings
- No network dependency for coloring/export
- Deterministic local export with atomic writes
- Prevent duplicate export runs while an export is already in progress
- Keep file-import disk reads off the main thread
- Restore imported drawings from iCloud when local files are missing
- Retry imported drawing restore after launch and on app foreground to handle delayed iCloud availability
- Persist per-template coloring strokes locally and mirror them to iCloud for reinstall recovery

4) Testing priorities
- View-model state transitions (scene switching, coloring, clearing)
- Export state handling
- Template image synchronization when switching between same-size templates
- Imported drawing reset flows (single delete and delete-all confirmation behavior)

## Architecture snapshot (current)
- App entry: `/Users/donnoel/Development/Coloring/Coloring/ColoringApp.swift`
- Root navigation: single Template Studio root in `/Users/donnoel/Development/Coloring/Coloring/ContentView.swift`
- Template view model: `/Users/donnoel/Development/Coloring/Coloring/ViewModels/TemplateStudioViewModel.swift`
- Services:
  - `/Users/donnoel/Development/Coloring/Coloring/Services/TemplateLibraryService.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Services/TemplateArtworkExportService.swift`
- Core drawing UI:
  - `/Users/donnoel/Development/Coloring/Coloring/Views/TemplateStudioView.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Views/PencilCanvasView.swift`

## Concurrency rules (important)
- Keep SwiftUI/view-model state on the main actor.
- Keep export persistence in a service actor.
- Use atomic file writes for exported PNG data.

## Behavior invariants (do not regress)
- Template Studio works offline for built-in templates.
- Imported templates are saved locally with atomic writes.
- Imported templates are mirrored to iCloud when available and restored locally if missing.
- Template stroke progress is saved per drawing and restored from iCloud after reinstall.
- The In Progress folder automatically includes drawings that have saved strokes or fills, excludes drawings marked Completed, and removes drawings when both strokes and fills are cleared.
- The In Progress chip displays the current number of non-completed drawings with saved strokes or fills.
- Favorites and Completed folder membership persist locally per drawing, and Recent reflects the most recently opened drawings first.
- Apple Pencil strokes can be exported composited with the selected template.
- Export canvas geometry must preserve the live template aspect ratio to keep coloring aligned with line art.
- Library sidebar lists both built-in and imported templates together.
- Built-in landscape templates request landscape orientation, and built-in portrait templates request portrait orientation.
- Pencil gesture behavior remains native-first: squeeze for eraser, tap for tool/color picker.
- Brush selection should rely on the native PencilKit picker rather than duplicate in-app brush chrome.
- Layer controls should be launched from the sidebar, and destructive clear/delete actions should require explicit confirmation.
- Fill taps should map to the exact visible region the user selects, regardless of zoom level or source image orientation.
- The PencilKit eraser should also remove the touched fill region when fill overlay is present in coloring mode.
- Undo and redo should preserve the combined per-template edit history for strokes, fills, fill erasing, clears, and layer operations.
- The floating palette should support top/bottom placement, auto-hide during active stroke coloring, and return after roughly one second of drawing inactivity.
- Studio and Gallery chrome should adapt to the current system light/dark appearance without changing canvas readability or altering artwork colors.
- The native PencilKit tool picker should keep a stable light appearance and color mapping so black/white inks do not invert when the system appearance changes.

## UX rules
- iPad-first layout with clear template navigation.
- Coloring should prioritize direct Apple Pencil drawing.
- Export status and errors must be visible in plain language.
- Template Studio should prioritize full-screen coloring, with file/template management available on demand.

## Coding conventions
- Keep scene data declarative and local.
- Use small models/services; avoid broad global state.
- Prefer deterministic, testable view-model logic.

## Build/run notes
- Supported platform: iOS/iPad simulator (`TARGETED_DEVICE_FAMILY = 2`).
- Warning policy: treat warnings as errors for all changes.
- Build command:
  - `xcodebuild -project Coloring.xcodeproj -scheme Coloring -destination 'generic/platform=iOS Simulator' clean build`

## Near-term priorities
- Add title search for templates.
- Add custom color palette management.
- Add broader automated test coverage and reduce simulator test flakiness.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
