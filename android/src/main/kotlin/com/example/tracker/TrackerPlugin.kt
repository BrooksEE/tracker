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
import com.example.tracker.Tracker
//import android.annotation.RequiresApi
//import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.plugin.common.MethodChannel
//import android.util.Log
//import android.content.Intent
import android.os.Messenger
import android.os.Bundle
import android.widget.Toast
import android.os.Handler
import android.os.Message
import java.util.HashMap

/** TrackerPlugin */
class TrackerPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private lateinit var activity: Activity

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tracker")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if(call.method == "start") {
      Log.d("LOC", "start called")
      val permission = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
      if (permission == PackageManager.PERMISSION_DENIED) {
        result.error("PERMISSION_DENIED", "Location Permissions Have Not Been Granted", null);
      } else if(permission == PackageManager.PERMISSION_GRANTED) { // Request location updates and when an update is
        start(call.argument("title"), call.argument("text"))
        result.success(true)
      }
    } else if (call.method == "stop") {
      stop();
      result.success(true)
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

  fun stop() {
    Log.i("LOC", "stopping service")
    Intent(context, Tracker::class.java).also { intent ->
      context.stopService(intent)
      Log.i("LOC", "stopping service2")
    }
  }

  fun start(title: String?, text: String?) {
    Log.d("LOC", "ACTIVITY: " + activity.toString())
    val messenger = Messenger(IncomingHandler(channel))
    Intent(context, Tracker::class.java).also { intent ->
      intent.putExtra("messenger", messenger)
      if(title != null) {
        intent.putExtra("title", title)
      }
      if(text != null) {
        intent.putExtra("text", text)
      }
      context.startForegroundService(intent)
      Log.i("LOC", "starting service2")
    }
  }
  inner class IncomingHandler(channel: MethodChannel?) : Handler() {
    override fun handleMessage(msg: Message) {
      val bundle: Bundle = msg.getData()
      val map: String? = bundle.getString("loc")
      channel?.invokeMethod("onLocation", map)
      //Toast.makeText(outer, result, Toast.LENGTH_SHORT).show()
    }
  }

}