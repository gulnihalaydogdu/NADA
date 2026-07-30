import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SplashController {
    static let splashDuration: Duration = .seconds(1.5)
    static let inactivityTimeout: TimeInterval = 5 * 60

    private static let lastBackgroundKey = "nada.lastBackgroundDate"

    /// Starts true so Welcome never flashes before splash on cold start.
    private(set) var isShowingSplash = true
    private var hideTask: Task<Void, Never>?
    private var backgroundEnteredAt: Date?
    private var enteredBackgroundThisSession = false

    /// Every cold start (incl. app switcher kill): 1.5s splash.
    func handleColdStart() {
        showSplash(for: Self.splashDuration)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            enteredBackgroundThisSession = true
            recordBackgroundEntry()
        case .active:
            guard enteredBackgroundThisSession else { return }
            enteredBackgroundThisSession = false
            handleResumeFromBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func recordBackgroundEntry() {
        let now = Date()
        backgroundEnteredAt = now
        UserDefaults.standard.set(now, forKey: Self.lastBackgroundKey)
    }

    /// Warm resume after 5+ min in background: 1.5s splash.
    private func handleResumeFromBackground() {
        guard elapsedSinceBackground >= Self.inactivityTimeout else { return }
        showSplash(for: Self.splashDuration)
    }

    private var elapsedSinceBackground: TimeInterval {
        if let backgroundEnteredAt {
            return Date().timeIntervalSince(backgroundEnteredAt)
        }
        if let lastBackground = UserDefaults.standard.object(forKey: Self.lastBackgroundKey) as? Date {
            return Date().timeIntervalSince(lastBackground)
        }
        return 0
    }

    private func showSplash(for duration: Duration) {
        isShowingSplash = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isShowingSplash = false
        }
    }
}
