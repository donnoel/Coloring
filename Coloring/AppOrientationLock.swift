import Foundation
import UIKit

enum AppOrientationLock {
    private static let lock = NSLock()
    private static var storedMask: UIInterfaceOrientationMask = .all

    static var currentMask: UIInterfaceOrientationMask {
        lock.withLock { storedMask }
    }

    static func setMask(_ mask: UIInterfaceOrientationMask) {
        lock.withLock {
            storedMask = mask
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationLock.currentMask
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
