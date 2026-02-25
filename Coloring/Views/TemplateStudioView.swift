import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TemplateStudioView: View {
    private static let defaultSidebarWidth: Double = 390
    private static let sidebarMinWidth: CGFloat = 300
    private static let sidebarMaxWidth: CGFloat = 560
    private enum PalettePlacement: String {
        case bottom
        case top
    }

    @Environment(\.scenePhase) private var scenePhase
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
    @State private var isPaletteVisible = true
    @State private var paletteAutoShowTask: Task<Void, Never>?
    @State private var requestedCanvasOrientation: ColoringTemplate.CanvasOrientation = .any
    @SceneStorage("templateStudio.sidebarWidth") private var sidebarWidth: Double = Self.defaultSidebarWidth
    @SceneStorage("templateStudio.palettePlacement") private var palettePlacementRawValue: String = PalettePlacement.bottom.rawValue
    @State private var sidebarResizeStartWidth: Double?
    @State private var sidebarStoredVerticalOffset: CGFloat = 0
    @State private var sidebarRestoreRequestID: Int = 0

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
            applyCanvasOrientationForSelectedTemplate(force: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await viewModel.refreshTemplatesFromStorage()
                await MainActor.run {
                    applyCanvasOrientationForSelectedTemplate(force: true)
                }
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
            applyCanvasOrientationForSelectedTemplate()
        }
        .onChange(of: viewModel.isFillModeActive) { _, isFillModeActive in
            if isFillModeActive {
                showPaletteImmediately()
            }
        }
        .onChange(of: columnVisibility) { oldValue, newValue in
            let wasSidebarHidden = oldValue == .detailOnly
            let isSidebarVisible = newValue != .detailOnly
            if wasSidebarHidden && isSidebarVisible {
                requestSidebarScrollRestore()
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
        .onAppear {
            requestSidebarScrollRestore()
            applyCanvasOrientationForSelectedTemplate(force: true)
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
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
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
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .background(
            SidebarScrollConfigurator(
                storedVerticalOffset: $sidebarStoredVerticalOffset,
                restoreRequestID: sidebarRestoreRequestID
            )
        )
        .scrollContentBackground(.hidden)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
        .navigationSplitViewColumnWidth(
            min: Self.sidebarMinWidth,
            ideal: CGFloat(sidebarWidth),
            max: Self.sidebarMaxWidth
        )
        .toolbar(.hidden, for: .navigationBar)
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
                .fill(.ultraThinMaterial)
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
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
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
                        .background(Color.white.opacity(0.58), in: Circle())
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
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.55), lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
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
        viewModel.filteredTemplates.sorted { lhs, rhs in
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
                        Text(category.name)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.selectedCategoryFilter == category.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(.systemGray5),
                                in: Capsule()
                            )
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
                onDrawingChanged: { drawing in
                    viewModel.updateDrawing(drawing)
                },
                onStrokeInteractionChanged: { isActive in
                    handleStrokeInteractionChanged(isActive)
                },
                fillMode: viewModel.isFillModeActive,
                selectedFillColor: viewModel.selectedFillColor?.uiColor,
                fillImage: viewModel.currentFillImage,
                onFillTap: { normalizedPoint in
                    viewModel.handleFillTap(at: normalizedPoint)
                },
                belowLayerImage: viewModel.belowLayerImage,
                aboveLayerImage: viewModel.aboveLayerImage,
                brushTool: viewModel.currentBrushTool
            )

            VStack(spacing: 0) {
                if isPaletteAtTop {
                    paletteBar
                        .padding(.top, 20)
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
            selectedColorID: $viewModel.selectedFillColorID,
            canUndoFill: viewModel.canUndoFill,
            canRedoFill: viewModel.canRedoFill,
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
            onUndoFill: { viewModel.undoFillStep() },
            onRedoFill: { viewModel.redoFillStep() }
        )
        .padding(.horizontal, 20)
        .opacity((isPaletteVisible || viewModel.isFillModeActive) ? 1 : 0)
        .offset(y: (isPaletteVisible || viewModel.isFillModeActive) ? 0 : paletteHiddenOffset)
        .allowsHitTesting(isPaletteVisible || viewModel.isFillModeActive)
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: [
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
                        sidebarResizeStartWidth = sidebarWidth
                    }

                    guard let sidebarResizeStartWidth else {
                        return
                    }

                    let proposedWidth = sidebarResizeStartWidth + Double(value.translation.width)
                    sidebarWidth = min(
                        max(proposedWidth, Double(Self.sidebarMinWidth)),
                        Double(Self.sidebarMaxWidth)
                    )
                }
                .onEnded { _ in
                    sidebarResizeStartWidth = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize library sidebar")
        .accessibilityHint("Drag left or right to adjust the drawing library width.")
    }

    private var libraryHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 8) {
                sidebarMetricPill(value: sortedTemplates.count, label: "Visible")
                sidebarMetricPill(value: viewModel.templates.filter(\.isImported).count, label: "Imported")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
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
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleStrokeInteractionChanged(_ isActive: Bool) {
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

    private func requestSidebarScrollRestore() {
        sidebarRestoreRequestID &+= 1
    }

    private func applyCanvasOrientationForSelectedTemplate(force: Bool = false) {
        let desiredOrientation = viewModel.selectedTemplate?.canvasOrientation ?? .any
        guard force || desiredOrientation != requestedCanvasOrientation else {
            return
        }

        requestedCanvasOrientation = desiredOrientation

        AppOrientationLock.setMask(desiredOrientation.interfaceOrientationMask)

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }

        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: desiredOrientation.interfaceOrientationMask)
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

private extension ColoringTemplate.CanvasOrientation {
    var interfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .any:
            return .all
        case .landscape:
            return .landscape
        case .portrait:
            return .portrait
        }
    }
}

private struct SidebarScrollConfigurator: UIViewRepresentable {
    @Binding var storedVerticalOffset: CGFloat
    let restoreRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(storedVerticalOffset: $storedVerticalOffset)
    }

    func makeUIView(context: Context) -> ProbeView {
        let probeView = ProbeView()
        probeView.restoreRequestID = restoreRequestID
        probeView.onScrollOffsetChanged = { [weak coordinator = context.coordinator] offset in
            coordinator?.updateStoredOffset(offset)
        }
        return probeView
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.storedVerticalOffset = storedVerticalOffset
        uiView.restoreRequestID = restoreRequestID
    }

    final class Coordinator {
        private var storedVerticalOffset: Binding<CGFloat>

        init(storedVerticalOffset: Binding<CGFloat>) {
            self.storedVerticalOffset = storedVerticalOffset
        }

        func updateStoredOffset(_ offset: CGFloat) {
            let normalizedOffset = max(0, offset)
            guard abs(storedVerticalOffset.wrappedValue - normalizedOffset) > 0.5 else {
                return
            }

            storedVerticalOffset.wrappedValue = normalizedOffset
        }
    }
}

private final class ProbeView: UIView {
    var storedVerticalOffset: CGFloat = 0
    var restoreRequestID: Int = 0 {
        didSet {
            guard restoreRequestID != oldValue else {
                return
            }

            pendingRestoreRequestID = restoreRequestID
            restoreOffsetIfRequested()
        }
    }

    var onScrollOffsetChanged: ((CGFloat) -> Void)?

    private weak var configuredScrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var pendingRestoreRequestID: Int?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureEnclosingScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureEnclosingScrollViewIfNeeded()
    }

    private func configureEnclosingScrollViewIfNeeded() {
        if let configuredScrollView, configuredScrollView.window != nil {
            applyConfiguration(to: configuredScrollView)
            observeContentOffset(of: configuredScrollView)
            restoreOffsetIfRequested()
            return
        }

        var currentView: UIView? = superview
        while let candidate = currentView {
            if let scrollView = candidate as? UIScrollView {
                applyConfiguration(to: scrollView)
                observeContentOffset(of: scrollView)
                configuredScrollView = scrollView
                restoreOffsetIfRequested()
                return
            }
            currentView = candidate.superview
        }
    }

    private func applyConfiguration(to scrollView: UIScrollView) {
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.refreshControl = nil
    }

    private func observeContentOffset(of scrollView: UIScrollView) {
        if configuredScrollView === scrollView, contentOffsetObservation != nil {
            return
        }

        contentOffsetObservation?.invalidate()
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            self?.applyConfiguration(to: scrollView)
            let normalizedOffset = max(0, scrollView.contentOffset.y)
            self?.onScrollOffsetChanged?(normalizedOffset)
            self?.restoreOffsetIfRequested()
        }
    }

    private func restoreOffsetIfRequested() {
        guard pendingRestoreRequestID != nil else {
            return
        }

        guard let scrollView = configuredScrollView else {
            return
        }

        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
            return
        }

        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let clampedOffset = min(max(storedVerticalOffset, 0), maxOffset)
        let currentOffset = scrollView.contentOffset.y
        let shouldRestoreFromTop = currentOffset <= 1
        let offsetAlreadyMatches = abs(currentOffset - clampedOffset) <= 1
        if shouldRestoreFromTop, !offsetAlreadyMatches {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: clampedOffset), animated: false)
        }

        self.pendingRestoreRequestID = nil
    }
}
