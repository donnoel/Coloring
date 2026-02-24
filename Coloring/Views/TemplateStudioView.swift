import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct TemplateStudioView: View {
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
    @State private var isLayerPanelPresented = false
    @State private var isBrushPanelPresented = false
    @State private var isCategoryManagementPresented = false

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
            "Delete All Imported Drawings",
            isPresented: $isDeleteAllImportedConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                confirmDeleteAllImported()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every imported drawing from this iPad and iCloud. Built-in drawings are not affected.")
        }
        .sheet(isPresented: $isCategoryManagementPresented) {
            CategoryManagementView(viewModel: viewModel)
        }
    }

    private var templateLibrary: some View {
        List {
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
                    Label("Export PNG", systemImage: "square.and.arrow.up")
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

                Button(role: .destructive) {
                    viewModel.clearDrawing()
                } label: {
                    Label("Clear Strokes", systemImage: "trash")
                }
                .disabled(viewModel.selectedTemplateImage == nil)

                Button(role: .destructive) {
                    viewModel.clearFills()
                } label: {
                    Label("Clear Fills", systemImage: "drop.triangle")
                }
                .disabled(viewModel.currentFillImage == nil)

                Button(role: .destructive) {
                    isDeleteAllImportedConfirmationPresented = true
                } label: {
                    Label("Delete All Imported Drawings", systemImage: "trash.slash")
                }
                .disabled(!viewModel.hasImportedTemplates)
            }

            Section("Status") {
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
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
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
        Button {
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
                        .foregroundStyle(.secondary)
                }

                if template.id == viewModel.selectedTemplateID {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                }
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

            libraryToggle
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var libraryToggle: some View {
        VStack {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.headline.weight(.semibold))
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle Library")
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard columnVisibility == .all else {
                                return
                            }

                            // Allow a simple, reliable swipe-left gesture on the toggle handle to close the library.
                            // Keep it conservative so it doesn't interfere with normal drawing gestures.
                            let isMostlyHorizontal = abs(value.translation.height) < 28
                            let isClosingSwipe = value.translation.width < -44
                            guard isMostlyHorizontal, isClosingSwipe else {
                                return
                            }

                            withAnimation(.easeInOut(duration: 0.2)) {
                                columnVisibility = .detailOnly
                            }
                        }
                )

                if viewModel.selectedTemplateImage != nil {
                    Button {
                        isLayerPanelPresented.toggle()
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.headline.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle Layers")
                    .popover(isPresented: $isLayerPanelPresented) {
                        LayerPanelView(viewModel: viewModel)
                    }

                    Button {
                        isBrushPanelPresented.toggle()
                    } label: {
                        Image(systemName: "paintbrush.pointed")
                            .font(.headline.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle Brushes")
                    .popover(isPresented: $isBrushPanelPresented) {
                        BrushCustomizationView(viewModel: viewModel)
                    }
                }

                Spacer()
            }
            .padding(.top, 10)
            .padding(.leading, 10)

            Spacer()
        }
        .allowsHitTesting(true)
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
                fillMode: viewModel.isFillModeActive,
                selectedFillColor: viewModel.selectedFillColor?.uiColor,
                fillImage: viewModel.currentFillImage,
                onFillTap: { imagePoint in
                    viewModel.handleFillTap(at: imagePoint)
                },
                belowLayerImage: viewModel.belowLayerImage,
                aboveLayerImage: viewModel.aboveLayerImage,
                brushTool: viewModel.currentBrushTool
            )

            VStack {
                Spacer()
                TemplatePaletteBarView(
                    isFillModeActive: $viewModel.isFillModeActive,
                    selectedColorID: $viewModel.selectedFillColorID,
                    onClearFills: {
                        viewModel.clearFills()
                    }
                )
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
