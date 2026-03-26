import Foundation

enum TemplateStrokeBoundaryResolver {
    static func shouldSplitPendingStroke(
        hasPendingStroke: Bool,
        previousStrokeCount: Int,
        updatedStrokeCount: Int
    ) -> Bool {
        hasPendingStroke && updatedStrokeCount > previousStrokeCount
    }
}
