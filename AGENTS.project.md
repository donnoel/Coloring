# AGENTS.project.md

# Coloring Project Guide for Agents

## Product intent
Coloring serves kids, families, and hobbyists who want a relaxing iPad coloring experience.
The app solves the need for ready-to-color, scene-based line art with a modern interface.
Success means users can pick a scene, color it intuitively, and export finished artwork quickly.

## Current product phase (MVP+ implemented)
1) MVP scope
- Studio + Gallery tab shell with a full-screen Apple Pencil studio (no Scene/Templates tab split)
- Unified sidebar list containing built-in and imported drawings
- PNG export + share flow
- Apple Pencil Template Studio with 80 manifest-driven built-in templates, including orientation metadata
- Built-in folder filters include In Progress (with a live count badge), Favorites, Recent, Completed, Imported (unassigned imported drawings), Landscape/Portrait, four complexity folders (Easy/Medium/Detailed/Dense), and manifest-driven shelf folders (Cozy, Nature, Animals, Fantasy, Patterns, Seasonal, Motorsport, Sci-Fi) with multi-folder membership support
- Folder order is user-reorderable via drag-and-drop in Manage Categories and persists locally
- Manage Categories supports creating, renaming, deleting, and reordering custom folders; imported drawings can be assigned into those folders
- Reversible hidden-template workflow (hide from library via context menu, restore from Hidden management view)
- Imported drawing templates from Photos/Files
- Immersive template workflow: always-full-screen canvas first, native PencilKit picker, native UIScrollView pan/zoom navigation, and sidebar-managed import/export/clear/rename/delete controls
- First-run premium onboarding flow with four visual pages covering Studio, import/coloring controls, organization + iCloud behavior, and Gallery export/share basics

2) Architecture boundaries
- SwiftUI views handle presentation and interaction only
- View model owns screen state and user actions
- Services own template catalog/import persistence, category state persistence, drawing persistence, and export/gallery IO

3) Reliability and UX goals
- Clean build with no warnings
- No network dependency for coloring/export
- Deterministic local export with atomic writes
- Prevent duplicate export runs while an export is already in progress
- Keep file-import disk reads off the main thread
- Restore imported drawings from iCloud when local files are missing
- Retry imported drawing restore after launch and on app foreground to handle delayed iCloud availability
- Persist per-template coloring strokes locally and mirror them to iCloud for reinstall recovery
- Keep hidden-template state durable so hidden items stay excluded from normal library browsing until unhidden

4) Testing priorities
- View-model state transitions (scene switching, coloring, clearing)
- Export state handling
- Template image synchronization when switching between same-size templates
- Imported drawing reset flows (single delete and delete-all confirmation behavior)
- Hidden/unhidden template flows and category-state sanitization

## Architecture snapshot (current)
- App entry: `/Users/donnoel/Development/Coloring/Coloring/ColoringApp.swift`
- Root navigation: Studio + Gallery `TabView` root in `/Users/donnoel/Development/Coloring/Coloring/ContentView.swift`
- Template view model: `/Users/donnoel/Development/Coloring/Coloring/ViewModels/TemplateStudioViewModel.swift`
- Services:
  - `/Users/donnoel/Development/Coloring/Coloring/Services/TemplateLibraryService.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Services/TemplateArtworkExportService.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Services/GalleryStoreService.swift`
- Gallery view model:
  - `/Users/donnoel/Development/Coloring/Coloring/ViewModels/GalleryViewModel.swift`
- Core drawing UI:
  - `/Users/donnoel/Development/Coloring/Coloring/Views/TemplateStudioView.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Views/PencilCanvasView.swift`
  - `/Users/donnoel/Development/Coloring/Coloring/Views/GalleryView.swift`

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
- The Imported folder should include only imported drawings that are not assigned to a custom folder.
- Favorites, Completed, Recent, Hidden, and custom category organization persist locally and mirror to iCloud for reinstall recovery.
- Gallery manifest and artwork files persist locally and mirror to iCloud for reinstall recovery.
- Hidden template IDs persist locally and hidden drawings remain excluded from normal browsing/category results until unhidden.
- Apple Pencil strokes can be exported composited with the selected template.
- Export canvas geometry must preserve the live template aspect ratio to keep coloring aligned with line art.
- Library sidebar lists both built-in and imported templates together.
- Library sidebar resize should remain responsive during drag and persist the chosen width after drag ends.
- Pencil gesture behavior remains native-first: squeeze for eraser, tap for tool/color picker.
- Brush selection should rely on the native PencilKit picker rather than duplicate in-app brush chrome.
- Fill color selection should rely on the active native PencilKit color rather than a separate in-app swatch palette.
- The native PencilKit palette should remain available in both draw and fill modes so users can change colors without mode switching.
- During first-run onboarding presentation, the native PencilKit palette should remain hidden and restore after onboarding is dismissed.
- Layer controls should be launched from the sidebar, and destructive clear/delete actions should require explicit confirmation.
- Fill taps should map to the exact visible region the user selects, regardless of zoom level or source image orientation.
- The PencilKit eraser should also remove the touched fill region when fill overlay is present in coloring mode.
- Undo and redo should preserve the combined per-template edit history for strokes, fills, fill erasing, clears, and layer operations.
- The floating palette should support top/bottom placement, auto-hide during active stroke coloring, and return after roughly one second of drawing inactivity.
- Studio and Gallery chrome should adapt to the current system light/dark appearance without changing canvas readability or altering artwork colors.
- The native PencilKit tool picker should stay in sync with the active system appearance while preserving light-canvas color mapping so black/white inks do not invert.
- Gallery exports and thumbnails should be normalized to an opaque white-backed image so transparent regions never appear dark in gallery previews.
- Gallery stage cards should render full-resolution artwork, while the bottom thumbnail rail should use compact thumbnails for performance.
- Sending artwork to Gallery should be best-effort and must not fail/share-block a completed PNG export.

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
- Deployment target: iOS 26.0 (use a matching modern Xcode toolchain, currently Xcode 26+).
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
