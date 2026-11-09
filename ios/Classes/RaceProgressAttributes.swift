// The race-progress Live Activity's data.
//
// Two identical copies: tracker/ios/Classes/RaceProgressAttributes.swift (the
// app side, which starts and updates the Live Activity) and
// oyo/ios/LiveActivity/RaceProgressAttributes.swift (the widget extension,
// which draws it). ActivityKit matches them by type name and fields, so change
// both together; `make check-live-activity` in oyo compares them.
// See oyo/docs/race-progress-notification.md.

import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
struct RaceProgressAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Distance covered, in `units`.
        var distance: Double
        /// Race distance, or nil while it isn't known yet.
        var total: Double?
        /// The start time when the clock should show, otherwise nil.
        var startDate: Date?
        /// Average pace, e.g. "08:29", or nil to hide it.
        var pace: String?
        /// "Waiting for start", "Off course", or nil.
        var status: String?
        /// The status line, e.g. "8.2 of 26.2 mi · 08:29/mi".
        var text: String
        /// Set when the session has ended.
        var finished: Bool
        /// Shown after the end, e.g. "Finished 3:42:10 · 08:29/mi".
        var resultText: String?
    }

    /// The session token from the app (each race-screen visit is a new one).
    var token: String
    /// The race name.
    var title: String
    /// "mi" or "km".
    var units: String
    /// The race theme's primary and secondary colors (ARGB), if any.
    var primaryColor: Int?
    var secondaryColor: Int?
}
#endif
