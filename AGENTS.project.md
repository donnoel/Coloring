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
- Apple Pencil Template Studio with 20 built-in 4:3 line-art templates
- Imported drawing templates from Photos/Files
- Immersive template workflow: always-full-screen canvas first, native PencilKit picker, and sidebar-managed import/export/clear/rename/delete controls

2) Architecture boundaries
- SwiftUI views handle presentation and interaction only
- View model owns screen state and user actions
- Services own scene catalog and export IO
- Services own template catalog/import persistence and template export IO

3) Reliability and UX goals
- Clean build with no warnings
- No network dependency for coloring/export
- Deterministic local export with atomic writes

4) Testing priorities
- View-model state transitions (scene switching, coloring, clearing)
- Export state handling

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
- Apple Pencil strokes can be exported composited with the selected template.
- Library sidebar lists both built-in and imported templates together.
- Pencil gesture behavior remains native-first: squeeze for eraser, tap for tool/color picker.

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
- Add template category filtering and favorites.
- Add undo/redo for coloring actions.
- Add broader automated test coverage and reduce simulator test flakiness.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
