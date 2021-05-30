package com.example.tracker
import android.content.Intent
import android.app.PendingIntent
import android.app.Service
import android.os.Looper
import android.os.Handler
import android.os.Message
import android.os.HandlerThread
import android.os.Process
import android.widget.Toast
import android.os.IBinder
import android.util.Log
import android.app.Notification
import android.app.NotificationChannel
import android.app.Notification.Builder
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import android.app.Activity
import android.content.Context
import android.os.Build
import android.app.NotificationManager
import android.graphics.Color
import android.os.Bundle
import android.os.Messenger
import android.os.RemoteException
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity

import android.content.Context.NOTIFICATION_SERVICE
import android.app.ActivityManager
import android.os.Binder
import android.location.Location
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.OnCompleteListener
import com.google.android.gms.tasks.Task
import java.util.HashMap

import android.R.attr.data

import org.json.JSONObject




public class Tracker : Service() {
    private var data: Messenger? = null
    private var mFusedLocationClient: FusedLocationProviderClient? = null
    private var mLocationCallback: LocationCallback? = null

    fun onNewLocation(loc: Location) {
        val msg: Message = Message.obtain()
        val bundle = Bundle()
        val map: JSONObject = JSONObject()
        map.put("lat", loc.getLatitude())
        map.put("lon", loc.getLongitude())
        map.put("ele", loc.getAltitude())
        map.put("acc", loc.getAccuracy())
        map.put("epoch", loc.getTime())
        bundle.putString("loc", map.toString())
        msg.setData(bundle)
        try {
            data?.send(msg)
        } catch (e: RemoteException) {
            Log.e("LOC", e.toString())
        }
    }

    override fun onCreate() {
        Log.i("LOC", "onCreate()")
        super.onCreate()

        mFusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        mLocationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                super.onLocationResult(locationResult)
                //Log.i("LOC", locationResult.toString())
                onNewLocation(locationResult.getLastLocation())
            }
        }
        val locationRequest = LocationRequest.create()?.apply {
                interval = 1000
                fastestInterval = 500
                priority = LocationRequest.PRIORITY_HIGH_ACCURACY
        }

        try {
            mFusedLocationClient?.getLastLocation()
                    ?.addOnCompleteListener(object : OnCompleteListener<Location?> {
                        override fun onComplete(task: Task<Location?>) {
                            if (task.isSuccessful() && task.getResult() != null) {
                                //var loc : Location = task.getResult()
                                //onNewLocation(loc)
                                mFusedLocationClient?.requestLocationUpdates(
                                        locationRequest,
                                        mLocationCallback,
                                        Looper.getMainLooper())

                            } else {
                                Log.w("LOC", "Failed to get location.")
                            }
                        }
                    })
        } catch (unlikely: SecurityException) {
            Log.e("LOC", "Lost location permission.$unlikely")
        }

    }

    override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
        Log.i("BLE", "onStartCommand")
        data = intent.getParcelableExtra("messenger");
        Toast.makeText(this, "service starting", Toast.LENGTH_SHORT).show()
        val notificationIntent = Intent(this, FlutterActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, 0)

        val channelId =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    createNotificationChannel("my_service", "My Background Service")
                } else {
                    // If earlier version channel ID is not used
                    // https://developer.android.com/reference/android/support/v4/app/NotificationCompat.Builder.html#NotificationCompat.Builder(android.content.Context)
                    ""
                }

        val notification = Notification.Builder(this, channelId)
                .setContentTitle(intent.getStringExtra("title") ?: "TITLE")
                .setContentText(intent.getStringExtra("text") ?: "text")
                .setSmallIcon(R.drawable.ic_fg)
                .setContentIntent(pendingIntent)
                .build()
        startForeground(1, notification)

        return START_NOT_STICKY
    }

    private fun createNotificationChannel(channelId: String, channelName: String): String{
        val chan = NotificationChannel(channelId,
                channelName, NotificationManager.IMPORTANCE_NONE)
        chan.lightColor = Color.BLUE
        chan.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        val service = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        service.createNotificationChannel(chan)
        return channelId
    }

    override fun onBind(intent: Intent): IBinder? {
        // We don't provide binding, so return null
        return null
    }

    override fun onDestroy() {
        mFusedLocationClient?.removeLocationUpdates(mLocationCallback)
        Toast.makeText(this, "service done", Toast.LENGTH_SHORT).show()
//        if(result != null) {
//            scanner?.stopScan(result)
//        }
        super.onDestroy()
    }

}

