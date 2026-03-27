import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct TemplateStudioView: View {
    private static let defaultSidebarWidth: Double = 390
    private static let sidebarMinWidth: CGFloat = 300
    private static let sidebarMaxWidth: CGFloat = 640
    private enum PalettePlacement: String {
        case bottom
        case top
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: TemplateStudioViewModel

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    // Default to showing the library so the user always has a reliable starting point.
    // We still collapse to the canvas after a template is selected.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var templatePendingRename: ColoringTemplate?
    @State private var renameDraftTitle = ""
    @State private var templatePendingDeletion: ColoringTemplate?
    @State private var isDeleteAllImportedConfirmationPresented = false
    @State private var isClearStrokesConfirmationPresented = false
    @State private var isClearFillsConfirmationPresented = false
    @State private var isLayerPanelPresented = false
    @State private var isCategoryManagementPresented = false
    @State private var isHiddenManagementPresented = false
    @State private var isPaletteVisible = true
    @State private var paletteAutoShowTask: Task<Void, Never>?
    @SceneStorage("templateStudio.sidebarWidth") private var storedSidebarWidth: Double = Self.defaultSidebarWidth
    @State private var liveSidebarWidth: Double = Self.defaultSidebarWidth
    @SceneStorage("templateStudio.palettePlacement") private var palettePlacementRawValue: String = PalettePlacement.bottom.rawValue
    @State private var sidebarResizeStartWidth: Double?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            templateLibrary
        } detail: {
            templateWorkspace
        }
        .navigationSplitViewStyle(.prominentDetail)
        .task {
            await viewModel.loadTemplatesIfNeeded()
            viewModel.loadBrushPresetsIfNeeded()
            viewModel.loadCategoriesIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await viewModel.refreshTemplatesFromStorage()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                await importPhotoItem(newItem)
            }
        }
        .onChange(of: viewModel.selectedTemplateID) { _, _ in
            showPaletteImmediately()
        }
        .onChange(of: viewModel.isFillModeActive) { _, isFillModeActive in
            if isFillModeActive {
                showPaletteImmediately()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Rename Drawing", isPresented: isRenameAlertPresented) {
            TextField("Drawing name", text: $renameDraftTitle)

            Button("Cancel", role: .cancel) {
                clearRenameDraft()
            }

            Button("Save") {
                confirmRename()
            }
            .disabled(!canSaveRename)
        } message: {
            Text("Choose a new name for this imported drawing.")
        }
        .confirmationDialog(
            "Delete Drawing",
            isPresented: isDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            if let templatePendingDeletion {
                Button("Delete \"\(templatePendingDeletion.title)\"", role: .destructive) {
                    confirmDeletion()
                }
            }

            Button("Cancel", role: .cancel) {
                templatePendingDeletion = nil
            }
        } message: {
            Text("This removes the imported drawing from this iPad and iCloud.")
        }
        .confirmationDialog(
            "Clear Strokes",
            isPresented: $isClearStrokesConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Confirm Clear Strokes", role: .destructive) {
                viewModel.clearDrawing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all drawn strokes for the selected drawing.")
        }
        .confirmationDialog(
            "Clear Fills",
            isPresented: $isClearFillsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Confirm Clear Fills", role: .destructive) {
                viewModel.clearFills()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all fill colors for the selected drawing.")
        }
        .confirmationDialog(
            "Delete All Imported",
            isPresented: $isDeleteAllImportedConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Confirm Delete All", role: .destructive) {
                confirmDeleteAllImported()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every imported drawing from this iPad and iCloud. Built-in drawings are not affected.")
        }
        .sheet(isPresented: $isCategoryManagementPresented) {
            CategoryManagementView(viewModel: viewModel)
        }
        .sheet(isPresented: $isLayerPanelPresented) {
            LayerPanelView(viewModel: viewModel)
        }
        .sheet(isPresented: $isHiddenManagementPresented) {
            HiddenTemplatesView(viewModel: viewModel)
        }
        .onAppear {
            let clampedWidth = clampedSidebarWidth(storedSidebarWidth)
            liveSidebarWidth = clampedWidth
            if clampedWidth != storedSidebarWidth {
                storedSidebarWidth = clampedWidth
            }
        }
        .onDisappear {
            paletteAutoShowTask?.cancel()
            paletteAutoShowTask = nil
        }
    }

    private var templateLibrary: some View {
        List {
            Section {
                libraryHeroCard
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Import Drawings") {
                importControls
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                categoryFilterChips
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if sortedTemplates.isEmpty {
                    Text("No drawings available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTemplates) { template in
                        templateRow(template)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } header: {
                HStack {
                    Text("Drawings")
                    Spacer()
                    Button {
                        isHiddenManagementPresented = true
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isCategoryManagementPresented = true
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Artwork") {
                Button {
                    Task {
                        await viewModel.exportCurrentTemplate()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.selectedTemplateImage == nil || viewModel.isExporting)

                if viewModel.isExporting {
                    ProgressView("Exporting…")
                }

                if let exportedFileURL = viewModel.exportedFileURL {
                    ShareLink(item: exportedFileURL) {
                        Label("Share Export", systemImage: "paperplane")
                    }
                }

                Button {
                    isLayerPanelPresented = true
                } label: {
                    Label("Layers", systemImage: "square.3.layers.3d")
                }
                .disabled(viewModel.selectedTemplateImage == nil)

                Button(role: .destructive) {
                    isClearStrokesConfirmationPresented = true
                } label: {
                    Label("Clear Strokes", systemImage: "trash")
                }
                .disabled(viewModel.selectedTemplateImage == nil)

                Button(role: .destructive) {
                    isClearFillsConfirmationPresented = true
                } label: {
                    Label {
                        Text("Clear Fills")
                            .foregroundStyle(.red)
                    } icon: {
                        Image(systemName: "drop.triangle")
                    }
                }
                .disabled(viewModel.currentFillImage == nil)

                Button(role: .destructive) {
                    isDeleteAllImportedConfirmationPresented = true
                } label: {
                    Label {
                        Text("Delete All Imported")
                            .foregroundStyle(.red)
                    } icon: {
                        Image(systemName: "trash.slash")
                    }
                }
                .disabled(!viewModel.hasImportedTemplates)
            }

            Section {
                if let importStatusMessage = viewModel.importStatusMessage {
                    Text(importStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let importErrorMessage = viewModel.importErrorMessage {
                    Text(importErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let exportStatusMessage = viewModel.exportStatusMessage {
                    Text(exportStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let exportErrorMessage = viewModel.exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let drawingRestoreError = viewModel.drawingRestoreErrorMessage {
                    Label {
                        Text(drawingRestoreError)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .foregroundStyle(.orange)
                }

                Text("App Version \(appVersionText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
        .navigationSplitViewColumnWidth(
            min: Self.sidebarMinWidth,
            ideal: CGFloat(liveSidebarWidth),
            max: Self.sidebarMaxWidth
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "Unavailable"
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(liquidImportAccent)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add New Coloring Page")
                        .font(.headline.weight(.semibold))
                    Text("Import line-art from Photos or Files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    preferredItemEncoding: .automatic
                ) {
                    liquidImportButtonLabel(
                        title: "Photos",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isFileImporterPresented = true
                } label: {
                    liquidImportButtonLabel(
                        title: "Files",
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(elevatedSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(liquidImportAccent.opacity(0.75), lineWidth: 1)
                )
        }
    }

    private func liquidImportButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(controlSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(sidebarControlStroke, lineWidth: 1)
                )
        }
    }

    private var liquidImportAccent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.64, blue: 0.96),
                Color(red: 0.21, green: 0.84, blue: 0.65),
                Color(red: 0.98, green: 0.58, blue: 0.17)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func templateRow(_ template: ColoringTemplate) -> some View {
        let isSelected = template.id == viewModel.selectedTemplateID
        let isFavorite = viewModel.isFavorite(template.id)
        let isCompleted = viewModel.isCompleted(template.id)

        return Button {
            viewModel.selectTemplate(template.id)
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = .detailOnly
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(template.source == .imported ? "Imported" : template.category)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if template.isImported {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(importedTemplateBadgeFill, in: Circle())
                }

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.yellow)
                }

                if isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(templateRowFill(isSelected: isSelected))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(templateRowStroke(isSelected: isSelected), lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                viewModel.toggleFavorite(for: template.id)
            } label: {
                Label(isFavorite ? "Remove Favorite" : "Add Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }

            Button {
                viewModel.toggleCompleted(for: template.id)
            } label: {
                Label(isCompleted ? "Mark Incomplete" : "Mark Completed", systemImage: isCompleted ? "arrow.uturn.backward.circle" : "checkmark.seal")
            }

            Button {
                viewModel.hideTemplate(template.id)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }

            if template.isImported {
                Button {
                    startRename(template)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                if !viewModel.userCategories.isEmpty {
                    Menu {
                        Button {
                            viewModel.assignTemplate(template.id, toCategoryID: nil)
                        } label: {
                            Label("Imported (Default)", systemImage: "tray.and.arrow.down")
                        }

                        ForEach(viewModel.userCategories) { category in
                            Button {
                                viewModel.assignTemplate(template.id, toCategoryID: category.id)
                            } label: {
                                Label(category.name, systemImage: "folder")
                            }
                        }
                    } label: {
                        Label("Move to Category", systemImage: "folder")
                    }
                }

                Button(role: .destructive) {
                    requestDeletion(template)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if template.isImported {
                Button {
                    startRename(template)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)

                Button(role: .destructive) {
                    requestDeletion(template)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var sortedTemplates: [ColoringTemplate] {
        if viewModel.selectedCategoryFilter == TemplateCategory.recentCategory.id {
            return viewModel.filteredTemplates
        }

        return viewModel.filteredTemplates.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source == .imported
            }

            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.allCategories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedCategoryFilter = category.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.name)
                                .font(.caption.weight(.medium))

                            if category.id == TemplateCategory.inProgressCategory.id {
                                Text("\(viewModel.visibleInProgressTemplateIDs.count)")
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        viewModel.selectedCategoryFilter == category.id
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(categoryBadgeFill(isSelected: viewModel.selectedCategoryFilter == category.id), in: Capsule())
                            }
                        }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(categoryChipFill(isSelected: viewModel.selectedCategoryFilter == category.id), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        viewModel.selectedCategoryFilter == category.id
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var templateWorkspace: some View {
        ZStack {
            if let templateImage = viewModel.selectedTemplateImage {
                templateCanvas(templateImage: templateImage)
            } else if !viewModel.selectedTemplateID.isEmpty {
                ProgressView("Loading Drawing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Template Selected",
                    systemImage: "scribble.variable",
                    description: Text("Open Library to pick or import a drawing, then start coloring.")
                )
                .overlay(alignment: .bottom) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility = .all
                        }
                    } label: {
                        Label("Open Library", systemImage: "sidebar.leading")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func templateCanvas(templateImage: UIImage) -> some View {
        ZStack {
            Color.white

            PencilCanvasView(
                templateImage: templateImage,
                templateID: viewModel.selectedTemplateID,
                drawing: $viewModel.currentDrawing,
                drawingSyncToken: viewModel.drawingSyncToken,
                onDrawingChanged: { drawing in
                    viewModel.updateDrawing(drawing)
                },
                onStrokeInteractionChanged: { isActive in
                    handleStrokeInteractionChanged(isActive)
                },
                fillMode: viewModel.isFillModeActive,
                fillImage: viewModel.currentFillImage,
                onFillTap: { normalizedPoint, fillColor in
                    viewModel.handleFillTap(at: normalizedPoint, color: fillColor)
                },
                onFillErase: { normalizedPoint in
                    viewModel.handleFillErase(at: normalizedPoint)
                },
                onAppearanceStyleChanged: { previousTraitCollection in
                    viewModel.normalizeSelectedTemplateColoring(using: previousTraitCollection)
                },
                belowLayerImage: viewModel.belowLayerImage,
                aboveLayerImage: viewModel.aboveLayerImage,
                brushTool: viewModel.currentBrushTool
            )

            VStack(spacing: 0) {
                if isPaletteAtTop {
                    paletteBar
                        .padding(.top, 56)
                }

                Spacer(minLength: 0)

                if !isPaletteAtTop {
                    paletteBar
                        .padding(.bottom, 20)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isPaletteVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var paletteBar: some View {
        TemplatePaletteBarView(
            isFillModeActive: $viewModel.isFillModeActive,
            canUndo: viewModel.canUndoEdit,
            canRedo: viewModel.canRedoEdit,
            isPaletteAtTop: isPaletteAtTop,
            isLibraryVisible: columnVisibility != .detailOnly,
            onToggleLibrary: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                }
            },
            onTogglePalettePlacement: {
                togglePalettePlacement()
            },
            onUndo: { viewModel.undoLastEdit() },
            onRedo: { viewModel.redoLastEdit() }
        )
        .padding(.horizontal, 20)
        .opacity((isPaletteVisible || viewModel.isFillModeActive) ? 1 : 0)
        .offset(y: (isPaletteVisible || viewModel.isFillModeActive) ? 0 : paletteHiddenOffset)
        .allowsHitTesting(isPaletteVisible || viewModel.isFillModeActive)
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    Color(red: 0.10, green: 0.14, blue: 0.12),
                    Color(red: 0.12, green: 0.12, blue: 0.15)
                ]
                : [
                    Color(red: 0.93, green: 0.97, blue: 1.00),
                    Color(red: 0.95, green: 0.99, blue: 0.96),
                    Color(red: 0.98, green: 0.98, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sidebarResizeHandle: some View {
        VStack {
            Spacer(minLength: 120)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.24))
                .frame(width: 4, height: 76)
                .padding(.trailing, 2)
            Spacer(minLength: 120)
        }
        .frame(width: 18)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if sidebarResizeStartWidth == nil {
                        sidebarResizeStartWidth = liveSidebarWidth
                    }

                    guard let sidebarResizeStartWidth else {
                        return
                    }

                    let proposedWidth = sidebarResizeStartWidth + Double(value.translation.width)
                    liveSidebarWidth = clampedSidebarWidth(proposedWidth)
                }
                .onEnded { _ in
                    sidebarResizeStartWidth = nil
                    storedSidebarWidth = liveSidebarWidth
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize library sidebar")
        .accessibilityHint("Drag left or right to adjust the drawing library width.")
    }

    private var libraryCollapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = .detailOnly
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.subheadline.weight(.semibold))
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide Library")
        .accessibilityHint("Collapse the drawing library and focus on the canvas.")
    }

    private var libraryHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "paintpalette.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.62, blue: 0.97),
                                    Color(red: 0.18, green: 0.82, blue: 0.62)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drawing Library")
                            .font(.headline.weight(.semibold))
                        Text("Organize, import, and color with one workspace.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                libraryCollapseButton
            }

            HStack(spacing: 8) {
                sidebarMetricPill(value: sortedTemplates.count, label: "Visible")
                sidebarMetricPill(value: viewModel.visibleImportedTemplateCount, label: "Imported")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(elevatedSidebarFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(sidebarCardStroke, lineWidth: 1)
                )
        }
    }

    private func sidebarMetricPill(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSidebarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var elevatedSidebarFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color(red: 0.11, green: 0.15, blue: 0.21).opacity(0.96))
        }

        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var controlSidebarFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color(red: 0.14, green: 0.19, blue: 0.26).opacity(0.96))
        }

        return AnyShapeStyle(.regularMaterial)
    }

    private var sidebarControlStroke: Color {
        if colorScheme == .dark {
            return Color(red: 0.30, green: 0.39, blue: 0.50).opacity(0.8)
        }

        return Color.white.opacity(0.26)
    }

    private var sidebarCardStroke: Color {
        if colorScheme == .dark {
            return Color(red: 0.27, green: 0.36, blue: 0.47).opacity(0.82)
        }

        return Color.white.opacity(0.55)
    }

    private var importedTemplateBadgeFill: Color {
        if colorScheme == .dark {
            return Color(red: 0.22, green: 0.27, blue: 0.34).opacity(0.9)
        }

        return Color.white.opacity(0.58)
    }

    private func templateRowFill(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(red: 0.15, green: 0.31, blue: 0.49).opacity(0.42)
                : Color.accentColor.opacity(0.18)
        }

        if colorScheme == .dark {
            return Color(red: 0.13, green: 0.17, blue: 0.23).opacity(0.94)
        }

        return Color.white.opacity(0.68)
    }

    private func templateRowStroke(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }

        if colorScheme == .dark {
            return Color(red: 0.28, green: 0.36, blue: 0.47).opacity(0.78)
        }

        return Color.white.opacity(0.55)
    }

    private func categoryBadgeFill(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return isSelected
                ? Color(red: 0.80, green: 0.90, blue: 1.00).opacity(0.2)
                : Color(red: 0.18, green: 0.22, blue: 0.29).opacity(0.98)
        }

        return isSelected
            ? Color.white.opacity(0.72)
            : Color(.systemBackground).opacity(0.9)
    }

    private func categoryChipFill(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return isSelected
                ? Color(red: 0.13, green: 0.30, blue: 0.50).opacity(0.42)
                : Color(red: 0.14, green: 0.18, blue: 0.24).opacity(0.96)
        }

        return isSelected
            ? Color.accentColor.opacity(0.2)
            : Color(.systemGray5)
    }

    private func handleStrokeInteractionChanged(_ isActive: Bool) {
        viewModel.updateStrokeInteraction(isActive: isActive)

        guard !viewModel.isFillModeActive else {
            return
        }

        if isActive {
            paletteAutoShowTask?.cancel()
            paletteAutoShowTask = nil

            if isPaletteVisible {
                withAnimation(.easeOut(duration: 0.12)) {
                    isPaletteVisible = false
                }
            }
            return
        }

        paletteAutoShowTask?.cancel()
        paletteAutoShowTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPaletteVisible = true
                }
            }
        }
    }

    private func showPaletteImmediately() {
        paletteAutoShowTask?.cancel()
        paletteAutoShowTask = nil

        guard !isPaletteVisible else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isPaletteVisible = true
        }
    }

    private var palettePlacement: PalettePlacement {
        PalettePlacement(rawValue: palettePlacementRawValue) ?? .bottom
    }

    private var isPaletteAtTop: Bool {
        palettePlacement == .top
    }

    private var paletteHiddenOffset: CGFloat {
        isPaletteAtTop ? -24 : 24
    }

    private func togglePalettePlacement() {
        withAnimation(.easeInOut(duration: 0.2)) {
            palettePlacementRawValue = isPaletteAtTop
                ? PalettePlacement.bottom.rawValue
                : PalettePlacement.top.rawValue
            isPaletteVisible = true
        }
    }

    private func clampedSidebarWidth(_ proposedWidth: Double) -> Double {
        min(
            max(proposedWidth, Double(Self.sidebarMinWidth)),
            Double(Self.sidebarMaxWidth)
        )
    }

    private var canSaveRename: Bool {
        !renameDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { templatePendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameDraft()
                }
            }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { templatePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    templatePendingDeletion = nil
                }
            }
        )
    }

    private func startRename(_ template: ColoringTemplate) {
        templatePendingRename = template
        renameDraftTitle = template.title
    }

    private func clearRenameDraft() {
        templatePendingRename = nil
        renameDraftTitle = ""
    }

    private func confirmRename() {
        guard let templatePendingRename else {
            return
        }

        let updatedTitle = renameDraftTitle
        clearRenameDraft()
        Task {
            await viewModel.renameTemplate(templatePendingRename.id, to: updatedTitle)
        }
    }

    private func requestDeletion(_ template: ColoringTemplate) {
        templatePendingDeletion = template
    }

    private func confirmDeletion() {
        guard let templatePendingDeletion else {
            return
        }

        self.templatePendingDeletion = nil
        Task {
            await viewModel.deleteTemplate(templatePendingDeletion.id)
        }
    }

    private func confirmDeleteAllImported() {
        isDeleteAllImportedConfirmationPresented = false
        Task {
            await viewModel.deleteAllImportedTemplates()
        }
    }

    private func importPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    viewModel.reportImportFailure("Could not load selected photo data.")
                    selectedPhotoItem = nil
                }
                return
            }

            await viewModel.importTemplateImage(imageData, suggestedName: item.itemIdentifier)
            await MainActor.run {
                selectedPhotoItem = nil
            }
        } catch {
            await MainActor.run {
                viewModel.reportImportFailure("Could not read selected photo.")
                selectedPhotoItem = nil
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result,
              let fileURL = urls.first
        else {
            return
        }

        Task {
            let didStartScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: fileURL)
                }.value

                await viewModel.importTemplateImage(
                    data,
                    suggestedName: fileURL.deletingPathExtension().lastPathComponent
                )
            } catch {
                await MainActor.run {
                    viewModel.reportImportFailure("Could not import the selected file.")
                }
            }
        }
    }
}

private struct HiddenTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TemplateStudioViewModel

    var body: some View {
        NavigationStack {
            List {
                if viewModel.hiddenTemplates.isEmpty {
                    ContentUnavailableView(
                        "No Hidden Templates",
                        systemImage: "eye",
                        description: Text("Long-press a drawing and choose Hide to manage it here.")
                    )
                } else {
                    ForEach(viewModel.hiddenTemplates) { template in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.title)
                                    .font(.body.weight(.semibold))
                                Text(template.source == .imported ? "Imported" : template.category)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Unhide") {
                                viewModel.unhideTemplate(template.id)
                            }
                            .buttonStyle(.bordered)
                        }
                        .contextMenu {
                            Button {
                                viewModel.unhideTemplate(template.id)
                            } label: {
                                Label("Unhide", systemImage: "eye")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hidden")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Unhide All") {
                        viewModel.unhideAllTemplates()
                    }
                    .disabled(viewModel.hiddenTemplates.isEmpty)
                }
            }
        }
    }
}
