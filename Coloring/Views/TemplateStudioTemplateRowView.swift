import SwiftUI

struct TemplateStudioTemplateRowView<ContextMenuContent: View, SwipeActionsContent: View>: View {
    let template: ColoringTemplate
    let isSelected: Bool
    let isFavorite: Bool
    let isCompleted: Bool
    let progress: Double?
    let rowFill: Color
    let rowStroke: Color
    let importedBadgeFill: Color
    let onSelect: () -> Void
    @ViewBuilder let contextMenuContent: () -> ContextMenuContent
    @ViewBuilder let swipeActionsContent: () -> SwipeActionsContent

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(template.source == .imported ? "Imported" : template.category)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let progress {
                        progressStatus(progress)
                            .padding(.top, 3)
                    }
                }

                Spacer()

                if template.isImported {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(importedBadgeFill, in: Circle())
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
                    .fill(rowFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(rowStroke, lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuContent()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeActionsContent()
        }
    }

    private func progressStatus(_ progress: Double) -> some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))

                    Capsule()
                        .fill(isCompleted ? Color.green.opacity(0.78) : Color.accentColor.opacity(0.62))
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(width: 92, height: 4)

            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}
