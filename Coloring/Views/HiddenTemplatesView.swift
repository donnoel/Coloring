import SwiftUI

struct HiddenTemplatesView: View {
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
