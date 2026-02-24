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
                Section("Built-in Categories") {
                    ForEach(viewModel.builtInCategories) { category in
                        Label(category.name, systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Custom Categories") {
                    if viewModel.userCategories.isEmpty {
                        Text("No custom categories yet.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.userCategories) { category in
                            Label(category.name, systemImage: "folder.fill")
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
                        }
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

                ToolbarItem(placement: .primaryAction) {
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
