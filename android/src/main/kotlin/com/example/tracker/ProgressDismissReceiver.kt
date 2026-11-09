package com.example.tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires when the runner swipes the progress notification away. Google's Live
 * Update guidance: don't repost a dismissed one, so the rest of this session
 * stops posting the progress bar.
 */
class ProgressDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ProgressNotification.ACTION_DISMISSED) return
        val token = intent.getStringExtra(ProgressNotification.EXTRA_TOKEN)
        if (token != null && token == ProgressSession.token) {
            ProgressSession.dismissed = true
        }
    }
}
