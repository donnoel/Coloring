import Foundation

enum TemplateDeferredCloudRestoreRunner {
    static let defaultRetryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000
    ]

    @MainActor
    static func performDeferredCloudRestore(
        retryDelays: [UInt64]? = nil,
        sleep: @MainActor @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        isCancelled: @MainActor @escaping () -> Bool = { Task.isCancelled },
        reloadTemplates: @MainActor @escaping () async -> Bool,
        hasImportedTemplates: @MainActor @escaping () -> Bool
    ) async {
        let delays = retryDelays ?? defaultRetryDelays

        for delay in delays {
            await sleep(delay)
            if isCancelled() {
                return
            }

            let didReload = await reloadTemplates()
            if !didReload || hasImportedTemplates() {
                return
            }
        }
    }
}
