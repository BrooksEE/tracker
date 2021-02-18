package com.example.tracker

import android.app.Activity
import android.content.Context
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
import com.google.android.gms.location.*
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import android.content.pm.PackageManager
import android.util.Log
import android.app.Service
import android.content.ContentValues.TAG
import android.os.IBinder
import android.app.ActivityManager
import android.os.Binder
import android.os.Build
import android.app.Notification
import android.app.PendingIntent
import android.os.Looper
import android.app.Service.START_NOT_STICKY
import android.app.NotificationManager
import android.content.Context.NOTIFICATION_SERVICE
import android.os.HandlerThread
import android.app.NotificationChannel
//import android.support.v4.content.LocalBroadcastManager
import com.google.android.gms.tasks.OnCompleteListener
import com.google.android.gms.tasks.Task
import androidx.core.app.NotificationCompat
import androidx.work.Worker
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.ListenableWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
import kotlinx.coroutines.*
import android.R
import android.annotation.TargetApi
//import android.annotation.RequiresApi

/*
class LocationWorker(appContext: Context, workerParams: WorkerParameters): CoroutineWorker(appContext, workerParams) {
  private val notificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

  override suspend fun doWork(): Result {
    // Mark the Worker as important
    val progress = "Starting Download"
    setForeground(createForegroundInfo(progress))
    // Do the work here--in this case, upload the images.
    //uploadImages()

    Log.d("LOC", "HERE3")
    val request = LocationRequest()
    request.setInterval(5000)
    request.setFastestInterval(1000)
    request.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY)

    val client: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)

    // received, store the location in Firebase
    client.requestLocationUpdates(request, object : LocationCallback() {
      override fun onLocationResult(locationResult: LocationResult) {
        val location: Location = locationResult.getLastLocation()
        if (location != null) {
          //latitude = location.latitude
          //longitude = location.longitude
          Log.d("LOC", "location update $location")
          val loc = HashMap<String, Any>();
          loc.put("lat", location.latitude);
          loc.put("lon", location.longitude);
          loc.put("accuracy", location.accuracy);
          loc.put("provider", location.provider);
          loc.put("epoch", location.time);
          channel.invokeMethod("setLocation", loc);
        }
      }
    }, null)


    var idx = 0;
    while(true) {
      Log.d("LOC", "worker" + idx);
      delay(1000);
      idx++;
    }
    // Indicate whether the work finished successfully with the Result
    return Result.success()
  }

  private fun createForegroundInfo(progress: String): ForegroundInfo {
    val id = "TRACKID"//applicationContext.getString(R.string.notification_channel_id)
    val title = "TITLE"//applicationContext.getString(R.string.notification_title)
    val cancel = "CANCEL"//applicationContext.getString(R.string.cancel_download)
    // This PendingIntent can be used to cancel the worker
    val intent = WorkManager.getInstance(applicationContext).createCancelPendingIntent(getId())

    // Create a Notification channel if necessary
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      //createChannel()
      val name = "snap map fake location "
      val importance: Int = NotificationManager.IMPORTANCE_LOW
      val mChannel = NotificationChannel(id, name, importance)
      mChannel.enableLights(true)
      //mChannel.setLightColor(Color.BLUE)
      if (notificationManager != null) {
        notificationManager.createNotificationChannel(mChannel)
        //} else {
        //  stopSelf()
      }
    }

    val resId = applicationContext.getResources().getIdentifier("ic_launcher", "mipmap", applicationContext.getPackageName())
    Log.d("LOC","resId="+resId)
    val notification = NotificationCompat.Builder(applicationContext, id)
            .setContentTitle(title)
            .setTicker(title)
            .setContentText(progress)
            .setSmallIcon(R.drawable.ic_menu_week)//mipmap.ic_launcher)//applicationContext.getApplicationInfo().icon)//R.launcher_icon)
            .setOngoing(true)
            // Add the cancel action to the notification which can
            // be used to cancel the worker
            //.addAction(android.R.drawable.ic_delete, cancel, intent)
            .build()

    return ForegroundInfo(1, notification, FOREGROUND_SERVICE_TYPE_LOCATION)
  }

  //@RequiresApi(Build.VERSION_CODES.O)
  private fun createChannel() {
    // Create a Notification channel
  }
  /*
  @NonNull
  @TargetApi(26)
  @Synchronized
  private fun createChannel(): String? {
    val mNotificationManager: NotificationManager? = this.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
    val name = "snap map fake location "
    val importance: Int = NotificationManager.IMPORTANCE_LOW
    val mChannel = NotificationChannel("snap map channel", name, importance)
    mChannel.enableLights(true)
    mChannel.setLightColor(Color.BLUE)
    if (mNotificationManager != null) {
      mNotificationManager.createNotificationChannel(mChannel)
    } else {
      stopSelf()
    }
    return "snap map channel"
  }
  */
  companion object {
    const val KEY_INPUT_URL = "KEY_INPUT_URL"
    const val KEY_OUTPUT_FILE_NAME = "KEY_OUTPUT_FILE_NAME"
  }

}
*/

/** TrackerPlugin */
class TrackerPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private lateinit var activity: Activity

  private val PACKAGE_NAME = "com.brooksee.location"
  private val KEY_REQUESTING_LOCATION_UPDATES = "requesting_locaction_updates"
  private val CHANNEL_ID = "ForegroundService Kotlin"

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tracker")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext

  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else if(call.method == "start") {
      Log.d("LOC", "start called")
      val permission = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
      if (permission == PackageManager.PERMISSION_DENIED) {
        result.error("PERMISSION_DENIED", "Location Permissions Have Not Been Granted", null);
      } else if(permission == PackageManager.PERMISSION_GRANTED) { // Request location updates and when an update is
        start()
        result.success(true)
      }
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onDetachedFromActivity() {
    //TODO("Not yet implemented")
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    //TODO("Not yet implemented")
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity;
    Log.d("LOC", activity.toString())
  }

  override fun onDetachedFromActivityForConfigChanges() {
    //TODO("Not yet implemented")
  }

  fun start() {
    Log.d("LOC", "ACTIVITY: " + activity.toString())
    //val locWorkRequest: WorkRequest = OneTimeWorkRequestBuilder<LocationWorker>().build()
    //WorkManager.getInstance(context).enqueue(locWorkRequest)

    //val startIntent = Intent(context, TrackerPlugin::class.java)
    //ContextCompat.startForegroundService(activity, startIntent)
    //startService(activity, "Running");
    // Notification ID cannot be 0.
    //startForeground(1, notification)
  }

  /*
  override fun onBind(p0: Intent): IBinder? {
    Log.d("LOC", "onBind called")
    return null
  }

   */


  /*
  companion object {
    fun startService(context: Context, message: String) {
      Log.d("LOC", "HERE1")
      val startIntent = Intent(context, TrackerPlugin::class.java)
      ContextCompat.startForegroundService(context, startIntent)
      Log.d("LOC", "HERE2")
    }
    fun stopService(context: Context) {
      val stopIntent = Intent(context, TrackerPlugin::class.java)
      context.stopService(stopIntent)
    }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.d("LOC", "HERE3")
    val request = LocationRequest()
    request.setInterval(5000)
    request.setFastestInterval(1000)
    request.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY)

    val client: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)

    // received, store the location in Firebase
    client.requestLocationUpdates(request, object : LocationCallback() {
      override fun onLocationResult(locationResult: LocationResult) {
        val location: Location = locationResult.getLastLocation()
        if (location != null) {
          //latitude = location.latitude
          //longitude = location.longitude
          Log.d("LOC", "location update $location")
          val loc = HashMap<String, Any>();
          loc.put("lat", location.latitude);
          loc.put("lon", location.longitude);
          loc.put("accuracy", location.accuracy);
          loc.put("provider", location.provider);
          loc.put("epoch", location.time);
          channel.invokeMethod("setLocation", loc);
        }
      }
    }, null)
    //do heavy work on a background thread

    createNotificationChannel()
    val notificationIntent = Intent(this, TrackerPlugin::class.java)
    val pendingIntent = PendingIntent.getActivity(
            this,
            0, notificationIntent, 0
    )
    val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Foreground Service Kotlin Example")
            .setContentText("TEXT")
            //.setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .build()

    /*
    val pendingIntent: PendingIntent = Intent(this, TrackerPlugin::class.java).let { notificationIntent ->
              PendingIntent.getActivity(this, 0, notificationIntent, 0)
            }

    var CHANNEL_DEFAULT_IMPORTANCE: String = "CHANNEL_DEFAULT_IMPORTANCE"
    val notification: Notification = Notification.Builder(context, CHANNEL_DEFAULT_IMPORTANCE)
            .setContentTitle("TITLE")
            .setContentText("TEXT")
            //.setSmallIcon(R.drawable.icon)
            .setContentIntent(pendingIntent)
            .setTicker("TICKER")
            .build()
    */
    Log.d("LOC", "STARTING FOREGROUND")
    startForeground(notification, FOREGROUND_SERVICE_TYPE_LOCATION)
    //stopSelf();
    return START_NOT_STICKY
  }
  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val serviceChannel = NotificationChannel(CHANNEL_ID, "Foreground Service Channel",
              NotificationManager.IMPORTANCE_DEFAULT)
      val manager = getSystemService(NotificationManager::class.java)
      manager!!.createNotificationChannel(serviceChannel)
    }
  }

  */

//  private val mBinder: IBinder = LocalBinder()
//
//  /**
//   * Used to check whether the bound activity has really gone away and not unbound as part of an
//   * orientation change. We create a foreground service notification only if the former takes
//   * place.
//   */
//  private var mChangingConfiguration = false
//  private var mNotificationManager: NotificationManager? = null
//
//  /**
//   * Contains parameters used by [com.google.android.gms.location.FusedLocationProviderApi].
//   */
//  private var mLocationRequest: LocationRequest? = null
//
//  /**
//   * Provides access to the Fused Location Provider API.
//   */
//  private var mFusedLocationClient: FusedLocationProviderClient? = null
//
//  /**
//   * Callback for changes in location.
//   */
//  private var mLocationCallback: LocationCallback? = null
//  private var mServiceHandler: android.os.Handler? = null
//
//  /**
//   * The current location.
//   */
//  private var mLocation: Location? = null
//  override fun onCreate() {
//    mFusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
//    mLocationCallback = object : LocationCallback() {
//      override fun onLocationResult(locationResult: LocationResult) {
//        super.onLocationResult(locationResult)
//        onNewLocation(locationResult.getLastLocation())
//      }
//    }
//    createLocationRequest()
//    lastLocation
//    val handlerThread = HandlerThread(TAG)
//    handlerThread.start()
//    mServiceHandler = android.os.Handler(handlerThread.getLooper())
//    mNotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
//
//    // Android O requires a Notification Channel.
//    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//      val name: CharSequence = "HELLO WORLD" //getString(R.string.app_name)
//      // Create the channel for the notification
//      val mChannel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT)
//
//      // Set the Notification Channel for the Notification Manager.
//      mNotificationManager?.createNotificationChannel(mChannel)
//    }
//  }
//
//  override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
//    android.util.Log.i(TAG, "Service started")
//    val startedFromNotification: Boolean = intent.getBooleanExtra(EXTRA_STARTED_FROM_NOTIFICATION,
//            false)
//
//    // We got here because the user decided to remove location updates from the notification.
//    if (startedFromNotification) {
//      removeLocationUpdates()
//      stopSelf()
//    }
//    // Tells the system to not try to recreate the service after it has been killed.
//    return android.app.Service.START_NOT_STICKY
//  }
//
//  override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
//    super.onConfigurationChanged(newConfig)
//    mChangingConfiguration = true
//  }
//
//  override fun onBind(intent: Intent): IBinder {
//    // Called when a client (MainActivity in case of this sample) comes to the foreground
//    // and binds with this service. The service should cease to be a foreground service
//    // when that happens.
//    android.util.Log.i(TAG, "in onBind()")
//    stopForeground(true)
//    mChangingConfiguration = false
//    return mBinder
//  }
//
//  override fun onRebind(intent: Intent) {
//    // Called when a client (MainActivity in case of this sample) returns to the foreground
//    // and binds once again with this service. The service should cease to be a foreground
//    // service when that happens.
//    android.util.Log.i(TAG, "in onRebind()")
//    stopForeground(true)
//    mChangingConfiguration = false
//    super.onRebind(intent)
//  }
//
//  override fun onUnbind(intent: Intent): Boolean {
//    android.util.Log.i(TAG, "Last client unbound from service")
//
//    // Called when the last client (MainActivity in case of this sample) unbinds from this
//    // service. If this method is called due to a configuration change in MainActivity, we
//    // do nothing. Otherwise, we make this service a foreground service.
//    if (!mChangingConfiguration && requestingLocationUpdates(this)) {
//      android.util.Log.i(TAG, "Starting foreground service")
//      /*
//            // TODO(developer). If targeting O, use the following code.
//            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.O) {
//                mNotificationManager.startServiceInForeground(new Intent(this,
//                        LocationUpdatesService.class), NOTIFICATION_ID, getNotification());
//            } else {
//                startForeground(NOTIFICATION_ID, getNotification());
//            }
//             */startForeground(NOTIFICATION_ID, notification)
//    }
//    return true // Ensures onRebind() is called when a client re-binds.
//  }
//
//  override fun onDestroy() {
//    mServiceHandler?.removeCallbacksAndMessages(null)
//  }
//
//  /**
//   * Makes a request for location updates. Note that in this sample we merely log the
//   * [SecurityException].
//   */
//  fun requestLocationUpdates() {
//    android.util.Log.i(TAG, "Requesting location updates")
//    setRequestingLocationUpdates(this, true)
//    startService(Intent(getApplicationContext(), TrackerPlugin::class.java))
//    try {
//      mFusedLocationClient?.requestLocationUpdates(mLocationRequest,
//              mLocationCallback, Looper.myLooper())
//    } catch (unlikely: SecurityException) {
//      setRequestingLocationUpdates(this, false)
//      android.util.Log.e(TAG, "Lost location permission. Could not request updates. $unlikely")
//    }
//  }
//
//  /**
//   * Removes location updates. Note that in this sample we merely log the
//   * [SecurityException].
//   */
//  fun removeLocationUpdates() {
//    android.util.Log.i(TAG, "Removing location updates")
//    try {
//      mFusedLocationClient?.removeLocationUpdates(mLocationCallback)
//      setRequestingLocationUpdates(this, false)
//      stopSelf()
//    } catch (unlikely: SecurityException) {
//      setRequestingLocationUpdates(this, true)
//      android.util.Log.e(TAG, "Lost location permission. Could not remove updates. $unlikely")
//    }
//  }// Channel ID// Extra to help us figure out if we arrived in onStartCommand via the notification or not.
//
//  // The PendingIntent that leads to a call to onStartCommand() in this service.
//
//  // The PendingIntent to launch activity.
//
//  // Set the Channel ID for Android O.
//  /**
//   * Returns the [NotificationCompat] used as part of the foreground service.
//   */
//  private val notification: Notification
//    private get() {
//      val intent = Intent(this, TrackerPlugin::class.java)
//      val text: CharSequence = getLocationText(mLocation)
//
//      // Extra to help us figure out if we arrived in onStartCommand via the notification or not.
//      intent.putExtra(EXTRA_STARTED_FROM_NOTIFICATION, true)
//
//      // The PendingIntent that leads to a call to onStartCommand() in this service.
//      val servicePendingIntent: PendingIntent = PendingIntent.getService(this, 0, intent,
//              PendingIntent.FLAG_UPDATE_CURRENT)
//
//      // The PendingIntent to launch activity.
//      val activityPendingIntent: PendingIntent = PendingIntent.getActivity(this, 0,
//              Intent(this, TrackerPlugin::class.java), 0)
//      val builder: Notification.Builder = Notification.Builder(this)
////              .addAction(R.drawable.ic_launch, getString(R.string.launch_activity),
////                      activityPendingIntent)
////              .addAction(R.drawable.ic_cancel, getString(R.string.remove_location_updates),
////                      servicePendingIntent)
//              .setContentText(text)
//              .setContentTitle(getLocationTitle(this))
//              .setOngoing(true)
//              .setPriority(Notification.PRIORITY_HIGH)
////              .setSmallIcon(R.mipmap.ic_launcher)
//              .setTicker(text)
//              .setWhen(java.lang.System.currentTimeMillis())
//
//      // Set the Channel ID for Android O.
//      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//        builder.setChannelId(CHANNEL_ID) // Channel ID
//      }
//      return builder.build()
//    }
//
//  private val lastLocation: Unit
//    private get() {
//      try {
//        mFusedLocationClient?.getLastLocation()
//                ?.addOnCompleteListener(object : OnCompleteListener<Location?>() {
//                  override fun onComplete(@NonNull task: Task<Location?>) {
//                    if (task.isSuccessful() && task.getResult() != null) {
//                      mLocation = task.getResult()
//                    } else {
//                      android.util.Log.w(TAG, "Failed to get location.")
//                    }
//                  }
//                })
//      } catch (unlikely: SecurityException) {
//        android.util.Log.e(TAG, "Lost location permission.$unlikely")
//      }
//    }
//
//  private fun onNewLocation(location: Location) {
//    android.util.Log.i(TAG, "New location: $location")
//    mLocation = location
//
//    // Notify anyone listening for broadcasts about the new location.
//    //val intent = Intent(ACTION_BROADCAST)
//    //intent.putExtra(EXTRA_LOCATION, location)
//    //LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(intent)
//
//    // Update notification content if running as a foreground service.
//    if (serviceIsRunningInForeground(this)) {
//      mNotificationManager?.notify(NOTIFICATION_ID, notification)
//    }
//  }
//
//  /**
//   * Sets the location request parameters.
//   */
//  private fun createLocationRequest() {
//    mLocationRequest = LocationRequest()
//    mLocationRequest?.setInterval(UPDATE_INTERVAL_IN_MILLISECONDS)
//    mLocationRequest?.setFastestInterval(FASTEST_UPDATE_INTERVAL_IN_MILLISECONDS)
//    mLocationRequest?.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY)
//  }
//
//  /**
//   * Class used for the client Binder.  Since this service runs in the same process as its
//   * clients, we don't need to deal with IPC.
//   */
//  inner class LocalBinder : Binder() {
//    val service: LocationUpdatesService
//      get() = this@LocationUpdatesService
//  }
//
//  /**
//   * Returns true if this is a foreground service.
//   *
//   * @param context The [Context].
//   */
//  fun serviceIsRunningInForeground(context: Context): Boolean {
//    val manager: ActivityManager = context.getSystemService(
//            Context.ACTIVITY_SERVICE) as ActivityManager
//    for (service in manager.getRunningServices(Int.MAX_VALUE)) {
//      if (javaClass.getName() == service.service.getClassName()) {
//        if (service.foreground) {
//          return true
//        }
//      }
//    }
//    return false
//  }
//
//  companion object {
//    private const val PACKAGE_NAME = "com.google.android.gms.location.sample.locationupdatesforegroundservice"
//    private val TAG: String = LocationUpdatesService::class.java.getSimpleName()
//
//    /**
//     * The name of the channel for notifications.
//     */
//    private const val CHANNEL_ID = "channel_01"
//    const val ACTION_BROADCAST = PACKAGE_NAME + ".broadcast"
//    const val EXTRA_LOCATION = PACKAGE_NAME + ".location"
//    private const val EXTRA_STARTED_FROM_NOTIFICATION = PACKAGE_NAME +
//            ".started_from_notification"
//
//    /**
//     * The desired interval for location updates. Inexact. Updates may be more or less frequent.
//     */
//    private const val UPDATE_INTERVAL_IN_MILLISECONDS: Long = 10000
//
//    /**
//     * The fastest rate for active location updates. Updates will never be more frequent
//     * than this value.
//     */
//    private const val FASTEST_UPDATE_INTERVAL_IN_MILLISECONDS = UPDATE_INTERVAL_IN_MILLISECONDS / 2
//
//    /**
//     * The identifier for the notification displayed for the foreground service.
//     */
//    private const val NOTIFICATION_ID = 12345678
//  }
//
//
//  /**
//   * Returns true if requesting location updates, otherwise returns false.
//   *
//   * @param context The [Context].
//   */
//  fun requestingLocationUpdates(context: Context?): Boolean {
//    return false//PreferenceManager.getDefaultSharedPreferences(context)
//            //.getBoolean(KEY_REQUESTING_LOCATION_UPDATES, false)
//  }
//
//  /**
//   * Stores the location updates state in SharedPreferences.
//   * @param requestingLocationUpdates The location updates state.
//   */
//  fun setRequestingLocationUpdates(context: Context?, requestingLocationUpdates: Boolean) {
//    //PreferenceManager.getDefaultSharedPreferences(context)
//    //        .edit()
//    //        .putBoolean(KEY_REQUESTING_LOCATION_UPDATES, requestingLocationUpdates)
//    //        .apply()
//  }
//
//  /**
//   * Returns the `location` object as a human readable string.
//   * @param location  The [Location].
//   */
//  fun getLocationText(location: Location?): String {
//    return if (location == null) "Unknown location" else "(" + location.getLatitude() + ", " + location.getLongitude() + ")"
//  }
//
//  fun getLocationTitle(context: Context): String {
//    return "HERE I AM"//context.getString(R.string.location_updated,
//            //java.text.DateFormat.getDateTimeInstance().format(java.util.Date()))
//  }
}