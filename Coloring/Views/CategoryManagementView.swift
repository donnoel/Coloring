import SwiftUI

struct CategoryManagementView: View {
    @ObservedObject var viewModel: TemplateStudioViewModel
    @State private var isAddCategoryAlertPresented = false
    @State private var newCategoryName = ""
    @State private var editingCategory: TemplateCategory?
    @State private var editingName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Folders") {
                    if viewModel.reorderableCategories.isEmpty {
                        Text("No folders available.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.reorderableCategories) { category in
                            folderRow(category)
                        }
                        .onMove(perform: viewModel.moveCategories)
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    EditButton()

                    Button {
                        newCategoryName = ""
                        isAddCategoryAlertPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Category", isPresented: $isAddCategoryAlertPresented) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
                Button("Create") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        viewModel.createUserCategory(name: trimmed)
                    }
                    newCategoryName = ""
                }
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Enter a name for the new category.")
            }
            .alert("Rename Category", isPresented: isRenamingAlertPresented) {
                TextField("Category name", text: $editingName)
                Button("Cancel", role: .cancel) {
                    editingCategory = nil
                    editingName = ""
                }
                Button("Save") {
                    if let editingCategory {
                        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.renameUserCategory(editingCategory.id, to: trimmed)
                        }
                    }
                    editingCategory = nil
                    editingName = ""
                }
                .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Enter a new name for this category.")
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ category: TemplateCategory) -> some View {
        let row = HStack(spacing: 10) {
            Label(
                category.name,
                systemImage: category.isUserCreated ? "folder.fill" : "folder"
            )

            Spacer()

            Text(category.isUserCreated ? "Custom" : "Built-in")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if category.isUserCreated {
            row
                .contextMenu {
                    Button {
                        editingCategory = category
                        editingName = category.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        viewModel.deleteUserCategory(category.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteUserCategory(category.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        editingCategory = category
                        editingName = category.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        } else {
            row
                .foregroundStyle(.secondary)
        }
    }

    private var isRenamingAlertPresented: Binding<Bool> {
        Binding(
            get: { editingCategory != nil },
            set: { isPresented in
                if !isPresented {
                    editingCategory = nil
                    editingName = ""
                }
            }
        )
    }
}
