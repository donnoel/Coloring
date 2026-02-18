# Coloring

Coloring is an iPad-first SwiftUI coloring book app focused on full-screen outline templates, Apple Pencil drawing, and PNG export.

## Features
- Single full-screen coloring studio (no Scene/Templates tab switcher)
- Unified `Library` sidebar listing built-in and imported drawings in one clean list
- 20 built-in full-screen (4:3) line-art templates
- Import your own outline drawings from Photos or Files
- Native PencilKit tool picker controls (Apple-style pen/marker/eraser/color controls)
- Apple Pencil interaction support:
  - Squeeze switches to eraser
  - Double-tap opens the tool/color picker
- Always-full-screen canvas with no extra overlay chrome
- Pinch-to-zoom on the canvas for close coloring detail
- Sidebar-managed actions for `Export`, `Share`, `Clear`, plus imported drawing `Rename` and `Delete`
- Premium liquid-glass import card for Photos/Files
- PNG export with share sheet support
- Glass-inspired iPad UI with material layers and gradients

## Architecture
The app uses SwiftUI + MVVM:
- `Coloring/ViewModels/TemplateStudioViewModel.swift`: template loading, drawing state, import/export orchestration
- `Coloring/Services/TemplateLibraryService.swift`: built-in/imported template catalog + atomic import persistence
- `Coloring/Services/TemplateArtworkExportService.swift`: template+drawing composite PNG export
- `Coloring/Views/TemplateStudioView.swift`: split library + full-screen template workspace
- `Coloring/Views/PencilCanvasView.swift`: PencilKit canvas + native tool picker integration
- `Coloring/Models/*`: template and drawing models

## Requirements
- Xcode 17+
- iOS Simulator runtime

## Run
1. Open `/Users/donnoel/Development/Coloring/Coloring.xcodeproj`
2. Select scheme `Coloring`
3. Select an iPad simulator destination
4. Build and Run

## Test
Unit tests were updated for view-model behavior:
- `/Users/donnoel/Development/Coloring/ColoringTests/ColoringTests.swift`

Example command:
```bash
xcodebuild -project Coloring.xcodeproj -scheme Coloring -configuration Debug -destination 'platform=iOS Simulator,name=iPad (A16),OS=26.2' -only-testing:ColoringTests/testExportSetsShareURL test
```
