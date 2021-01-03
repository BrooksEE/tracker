package com.example.tracker

import androidx.annotation.NonNull
import android.Manifest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import android.content.Intent
import androidx.core.content.ContextCompat
import android.location.Location
//import com.google.android.gms.location.*

/** TrackerPlugin */
class TrackerPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tracker")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else if(call.method == "start") {
      start();
      result.success(true)
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  fun start() {
/*    val request = LocationRequest()
    request.setInterval(10000)
    request.setFastestInterval(5000)
    request.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY)
    val client: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(myAppContext())

    val permission = ContextCompat.checkSelfPermission(
        myAppContext(),
        Manifest.permission.ACCESS_FINE_LOCATION
    )
    if (permission == PackageManager.PERMISSION_GRANTED) { // Request location updates and when an update is
        // received, store the location in Firebase
        client.requestLocationUpdates(request, object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val location: Location = locationResult.getLastLocation()
                if (location != null) {
                    latitude = location.latitude
                    longitude = location.longitude
                    Log.d("Location Service", "location update $location")
                }
            }
        }, null)
    }
*/
/*
    val pendingIntent: PendingIntent =
            Intent(myAppContext(), TrackerPlugin::class.java).let { notificationIntent ->
              PendingIntent.getActivity(myAppContext(), 0, notificationIntent, 0)
            }
  */  /*
    val notification: Notification = Notification.Builder(this, CHANNEL_DEFAULT_IMPORTANCE)
            .setContentTitle(getText(R.string.notification_title))
            .setContentText(getText(R.string.notification_message))
            .setSmallIcon(R.drawable.icon)
            .setContentIntent(pendingIntent)
            .setTicker(getText(R.string.ticker_text))
            .build()

    // Notification ID cannot be 0.
    startForeground(ONGOING_NOTIFICATION_ID, notification)
     */
  }
}
