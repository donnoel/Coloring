import SwiftUI

struct TemplateStudioCategoryFilterChipsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let categories: [TemplateCategory]
    let selectedCategoryID: String
    let inProgressCategoryID: String
    let inProgressCount: Int
    let onSelectCategory: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories) { category in
                    let isSelected = selectedCategoryID == category.id

                    Button {
                        onSelectCategory(category.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.name)
                                .font(.caption.weight(.medium))

                            if category.id == inProgressCategoryID {
                                Text("\(inProgressCount)")
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(categoryBadgeFill(isSelected: isSelected), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(categoryChipFill(isSelected: isSelected), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
}
