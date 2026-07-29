import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SplashController {
    static let firstLaunchDuration: Duration = .seconds(2.75)
    static let timeoutResumeDuration: Duration = .seconds(1.2)
    /// Background / away time before the reopen splash plays.
    static let inactivityTimeout: TimeInterval = 5 * 60

    private static let firstLaunchKey = "nada.hasCompletedFirstLaunchSplash"
    private static let lastBackgroundKey = "nada.lastBackgroundDate"

    private(set) var isShowingSplash = false
    private var hideTask: Task<Void, Never>?
    private var backgroundEnteredAt: Date?
    private var enteredBackgroundThisSession = false

    /// Cold start: first install open, or reopen after inactivity timeout.
    func handleColdStart() {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: Self.firstLaunchKey) {
            showSplash(for: Self.firstLaunchDuration, markFirstLaunchComplete: true)
            return
        }

        if let lastBackground = defaults.object(forKey: Self.lastBackgroundKey) as? Date,
           Date().timeIntervalSince(lastBackground) >= Self.inactivityTimeout {
            showSplash(for: Self.timeoutResumeDuration)
            return
        }

        isShowingSplash = false
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

    func recordBackgroundEntry() {
        let now = Date()
        backgroundEnteredAt = now
        UserDefaults.standard.set(now, forKey: Self.lastBackgroundKey)
    }

    /// Warm resume after inactivity timeout (quick app-switch skips splash).
    func handleResumeFromBackground() {
        guard UserDefaults.standard.bool(forKey: Self.firstLaunchKey) else { return }
        guard elapsedSinceBackground >= Self.inactivityTimeout else { return }
        showSplash(for: Self.timeoutResumeDuration)
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

    private func showSplash(for duration: Duration, markFirstLaunchComplete: Bool = false) {
        isShowingSplash = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isShowingSplash = false
            if markFirstLaunchComplete {
                UserDefaults.standard.set(true, forKey: Self.firstLaunchKey)
            }
        }
    }
}
