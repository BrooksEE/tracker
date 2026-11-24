// Starts, updates and ends the race-progress Live Activity for the
// progressStart / progressUpdate / progressEnd channel calls. The same calls
// drive the Android notification; see oyo/docs/race-progress-notification.md.
//
// Rules (matching Android):
// - A Live Activity can only be requested while the app is in the foreground.
//   If that fails, the next update that arrives while the app is active (the
//   app sends one whenever it returns to the foreground) requests it.
// - If the participant swipes it away, it isn't requested again until the app
//   sends an update with `reshow` (the participant reopened the app).
// - Each update pushes staleDate 3 minutes out; the app sends at least one
//   update a minute while tracking, so a stale Live Activity means tracking
//   stopped (e.g. the app was force-quit).
// - iOS ends a Live Activity after 8 hours; the next foreground update
//   requests a fresh one.
// All calls arrive on the main thread.

import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
final class RaceProgressController {
    static let shared = RaceProgressController()

    private static let staleAfter: TimeInterval = 3 * 60

    private var token: String?
    private var attributes: RaceProgressAttributes?
    private var lastState: RaceProgressAttributes.ContentState?
    private var activity: Activity<RaceProgressAttributes>?
    private var active = false
    private var dismissed = false
    private var watchTask: Task<Void, Never>?

    func start(token: String, attributes: RaceProgressAttributes,
               state: RaceProgressAttributes.ContentState) {
        // A new session. Anything left over (an earlier visit to the race
        // screen, or a run before the app was relaunched) goes away at once;
        // with the default dismissal it would linger next to the new one.
        for old in Activity<RaceProgressAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        watchTask?.cancel()
        self.token = token
        self.attributes = attributes
        self.lastState = state
        activity = nil
        active = true
        dismissed = false
        requestIfPossible()
    }

    func update(token: String, state: RaceProgressAttributes.ContentState, reshow: Bool) {
        guard active, token == self.token else { return }
        lastState = state
        if reshow { dismissed = false }
        if let activity {
            let content = ActivityContent(state: state,
                                          staleDate: Date().addingTimeInterval(Self.staleAfter))
            Task { await activity.update(content) }
        } else {
            requestIfPossible()
        }
    }

    /// An empty `resultText` means there's nothing to show (the participant
    /// never got going), so the Live Activity is removed at once.
    func end(token: String, state: RaceProgressAttributes.ContentState,
             finished: Bool, resultText: String) {
        guard active, token == self.token else { return }
        active = false
        watchTask?.cancel()
        guard let activity else { return }
        self.activity = nil
        if resultText.isEmpty {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        var result = state
        result.finished = true
        result.resultText = resultText
        if finished, let total = result.total { result.distance = max(result.distance, total) }
        Task {
            await activity.end(ActivityContent(state: result, staleDate: nil),
                               dismissalPolicy: .default)
        }
    }

    private func requestIfPossible() {
        guard active, !dismissed, activity == nil,
              let attributes, let state = lastState else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Race progress: Live Activities are turned off for this app")
            return
        }
        // Requests fail in the background; the next foreground update retries.
        guard UIApplication.shared.applicationState == .active else { return }
        do {
            let content = ActivityContent(state: state,
                                          staleDate: Date().addingTimeInterval(Self.staleAfter))
            let started = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activity = started
            watch(started)
        } catch {
            print("Race progress: Live Activity request failed: \(error)")
        }
    }

    /// Notices the participant swiping it away, and iOS ending it (8 hours).
    private func watch(_ watched: Activity<RaceProgressAttributes>) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            for await state in watched.activityStateUpdates {
                await MainActor.run {
                    guard let self, self.activity?.id == watched.id else { return }
                    switch state {
                    case .dismissed:
                        self.activity = nil
                        if self.active { self.dismissed = true }
                    case .ended:
                        // Ended by iOS (e.g. the 8-hour limit) while the race
                        // goes on: the next foreground update starts a new one.
                        self.activity = nil
                    default:
                        break
                    }
                }
            }
        }
    }
}
#endif
