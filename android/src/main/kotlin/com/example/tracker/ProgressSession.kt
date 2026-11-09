package com.example.tracker

/**
 * The race-progress session shared by the plugin, the foreground service and
 * the dismiss receiver. See oyo/docs/race-progress-notification.md.
 *
 * The service posts notification 1 when it starts, which can land after the
 * plugin has already posted the progress bar, so the service builds its
 * notification from this state instead of always posting the plain one.
 * All access is on the main thread.
 */
object ProgressSession {
    /** Token of the current (or last) session, created by Dart. */
    var token: String? = null

    /** True between progressStart and progressEnd. */
    var active = false

    /** The runner swiped the progress notification away: don't repost it this session. */
    var dismissed = false

    /** The location service is running, so notification 1 belongs to it. */
    var serviceRunning = false

    /** Title of the progress notification (the race name). */
    var title: String = ""

    /** The race theme's primary and secondary colors (ARGB), if the app sent them. */
    var primaryColor: Int? = null
    var secondaryColor: Int? = null

    /** Latest full state from Dart. */
    var state: Map<String, Any?> = emptyMap()

    /** Title and text of the plain tracking notification, from the service's start intent. */
    var plainTitle: String = "Tracking"
    var plainText: String = "Tracking your race"
}
