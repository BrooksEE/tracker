package com.example.tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.drawable.IconCompat

/**
 * Builds and posts the tracking notifications.
 *
 * Notification 1 is the location service's foreground notification: the
 * race-progress bar while a progress session is active, otherwise a plain
 * "Tracking your race". Notification 2 is the result shown when a session
 * ends. See oyo/docs/race-progress-notification.md.
 */
object ProgressNotification {
    const val CHANNEL_ID = "tracker_progress"
    private const val OLD_CHANNEL_ID = "tracker"
    const val ONGOING_ID = 1
    const val RESULT_ID = 2
    const val ACTION_DISMISSED = "com.example.tracker.PROGRESS_DISMISSED"
    const val EXTRA_TOKEN = "token"

    /** Progress is drawn on a 0..PROGRESS_MAX scale (one segment of this length). */
    private const val PROGRESS_MAX = 1000
    private val TICKS = listOf(250, 500, 750)

    /**
     * Creates the visible tracking channel and removes the old one, which was
     * IMPORTANCE_NONE. An existing channel's importance can't be raised, so a
     * new channel ID is the only way to make the notification visible.
     */
    private var channelReady = false

    fun ensureChannel(context: Context) {
        if (channelReady || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        channelReady = true
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val chan = NotificationChannel(CHANNEL_ID, "Race tracking", NotificationManager.IMPORTANCE_LOW)
            chan.setShowBadge(false)
            chan.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            nm.createNotificationChannel(chan)
        }
        if (nm.getNotificationChannel(OLD_CHANNEL_ID) != null) {
            try {
                nm.deleteNotificationChannel(OLD_CHANNEL_ID)
            } catch (e: Exception) {
                // Refused while a foreground-service notification is still on it.
                Log.w("LOC", "Couldn't delete old notification channel: $e")
            }
        }
    }

    private fun smallIcon(context: Context): Int {
        // Each race app copies its own notification.png into the app's drawables.
        val id = context.resources.getIdentifier("notification", "drawable", context.packageName)
        return if (id != 0) id else R.drawable.ic_fg
    }

    private fun contentIntent(context: Context): PendingIntent? {
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.setPackage(null)
            ?.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            ?: return null
        return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun deleteIntent(context: Context, token: String?): PendingIntent {
        val intent = Intent(context, ProgressDismissReceiver::class.java)
            .setAction(ACTION_DISMISSED)
            .putExtra(EXTRA_TOKEN, token)
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun double(state: Map<String, Any?>, key: String): Double? =
        (state[key] as? Number)?.toDouble()

    // Approximate notification card backgrounds (they follow the wallpaper's
    // dynamic color, so these are typical values, not exact ones).
    private const val CARD_LIGHT = 0xFFE2E8DE.toInt()
    private const val CARD_DARK = 0xFF1E211C.toInt()
    private const val MIN_CONTRAST = 3.0

    /**
     * The race's brand color for the arrow, the completed bar and the ticks:
     * the theme's primary if it stands out on the card in the current light or
     * dark mode, else its secondary, else null (keep the neutral grey icon and
     * the system accent). theme.json is light-only, so a dark primary such as
     * a navy would vanish on a dark card without this check.
     */
    private fun brandColor(context: Context): Int? {
        val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val card = if (night) CARD_DARK else CARD_LIGHT
        return listOfNotNull(ProgressSession.primaryColor, ProgressSession.secondaryColor)
            .map { it or 0xFF000000.toInt() } // opaque
            .firstOrNull { ColorUtils.calculateContrast(it, card) >= MIN_CONTRAST }
    }

    private fun progressStyle(context: Context, fraction: Double): NotificationCompat.ProgressStyle {
        val brand = brandColor(context)
        val segment = NotificationCompat.ProgressStyle.Segment(PROGRESS_MAX)
        val tracker = IconCompat.createWithResource(context, R.drawable.ic_progress_position)
        val points = TICKS.map { NotificationCompat.ProgressStyle.Point(it) }
        if (brand != null) {
            segment.setColor(brand)
            points.forEach { it.setColor(brand) }
            tracker.setTint(brand)
        }
        return NotificationCompat.ProgressStyle()
            .setProgressSegments(listOf(segment))
            .setProgressPoints(points)
            .setProgress((fraction.coerceIn(0.0, 1.0) * PROGRESS_MAX).toInt())
            .setProgressTrackerIcon(tracker)
            .setProgressStartIcon(IconCompat.createWithResource(context, R.drawable.ic_progress_start))
            .setProgressEndIcon(IconCompat.createWithResource(context, R.drawable.ic_progress_finish))
    }

    private fun fraction(state: Map<String, Any?>): Double {
        val distance = double(state, "distance") ?: 0.0
        val total = double(state, "total") ?: return 0.0
        return if (total > 0) distance / total else 0.0
    }

    /** The plain foreground notification, used when no progress session is active. */
    fun buildPlain(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSmallIcon(smallIcon(context))
            .setContentTitle(ProgressSession.plainTitle)
            .setContentText(ProgressSession.plainText)
            .setContentIntent(contentIntent(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()

    /** The live progress bar for the current session. */
    fun buildProgress(context: Context): Notification {
        val state = ProgressSession.state
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            // Show the race progress on the lock screen even when sensitive
            // notification content is hidden; the channel setting isn't honored.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSmallIcon(smallIcon(context))
            .setContentTitle(ProgressSession.title)
            .setContentText(state["text"] as? String ?: "")
            .setContentIntent(contentIntent(context))
            .setDeleteIntent(deleteIntent(context, ProgressSession.token))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setStyle(progressStyle(context, fraction(state)))
            // Applied only on Android 16 QPR1+ by NotificationCompat; the system may still decline.
            .setRequestPromotedOngoing(true)

        val startEpoch = double(state, "startEpoch")
        if (startEpoch != null) {
            builder.setWhen((startEpoch * 1000).toLong())
                .setShowWhen(true)
                .setUsesChronometer(true)
        } else {
            builder.setShowWhen(false).setUsesChronometer(false)
        }
        // Status-bar chip on a promoted notification (API 36+; NotificationCompat checks).
        (state["chip"] as? String)?.let { builder.setShortCriticalText(it) }
        return builder.build()
    }

    /** What notification 1 should show right now. */
    fun buildOngoing(context: Context): Notification =
        if (ProgressSession.active && !ProgressSession.dismissed) buildProgress(context) else buildPlain(context)

    /** The result shown after a session ends: not ongoing, clock stopped, auto-cancels. */
    private fun buildResult(context: Context, text: String, finished: Boolean): Notification {
        val state = ProgressSession.state
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSmallIcon(smallIcon(context))
            .setContentTitle(ProgressSession.title)
            .setContentText(text)
            .setContentIntent(contentIntent(context))
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setUsesChronometer(false)
            .setStyle(progressStyle(context, if (finished) 1.0 else fraction(state)))
            .build()
    }

    private fun canPost(context: Context): Boolean {
        val enabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (!enabled) Log.i("LOC", "Race progress: notifications are disabled for this app")
        return enabled
    }

    /** Posts the current progress (or nothing if the session ended or was dismissed). */
    fun postProgress(context: Context) {
        if (!ProgressSession.active || ProgressSession.dismissed || !canPost(context)) return
        ensureChannel(context)
        try {
            NotificationManagerCompat.from(context).notify(ONGOING_ID, buildProgress(context))
        } catch (e: SecurityException) {
            Log.w("LOC", "Race progress: can't post notification: $e")
        }
    }

    /**
     * Ends the session: notification 1 goes back to the plain tracking
     * notification while the service still runs (cancel() would be a no-op on
     * a foreground notification), or is removed if there's no service (sim
     * mode); then the result goes on notification 2.
     */
    fun postEnd(context: Context, text: String, finished: Boolean) {
        val nm = NotificationManagerCompat.from(context)
        try {
            if (ProgressSession.serviceRunning) {
                // A dismissed notification stays dismissed.
                if (!ProgressSession.dismissed && canPost(context)) nm.notify(ONGOING_ID, buildPlain(context))
            } else {
                nm.cancel(ONGOING_ID)
            }
            // Empty text: the runner never got going, so there's no result to show.
            if (text.isNotEmpty() && canPost(context)) nm.notify(RESULT_ID, buildResult(context, text, finished))
        } catch (e: SecurityException) {
            Log.w("LOC", "Race progress: can't post notification: $e")
        }
    }

    fun cancelResult(context: Context) {
        NotificationManagerCompat.from(context).cancel(RESULT_ID)
    }
}
