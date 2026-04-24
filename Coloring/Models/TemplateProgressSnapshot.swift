import Foundation

struct TemplateProgressSnapshot: Codable, Equatable, Sendable {
    let templateID: String
    let estimatedProgress: Double
    let updatedAt: Date

    init(templateID: String, estimatedProgress: Double, updatedAt: Date = Date()) {
        self.templateID = templateID
        self.estimatedProgress = min(max(estimatedProgress, 0), 0.99)
        self.updatedAt = updatedAt
    }
}
