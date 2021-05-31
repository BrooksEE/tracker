import Flutter
import UIKit
import CoreLocation

public class SwiftTrackerPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  var locationManager: CLLocationManager?
  private var startResult: FlutterResult?
  var channel : FlutterMethodChannel?
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel:FlutterMethodChannel = FlutterMethodChannel(name: "tracker", binaryMessenger: registrar.messenger())
    let instance = SwiftTrackerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.channel = channel
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if(call.method == "start") {
	startResult = result
        start()
        //result(true)
    } else if(call.method == "stop") {
        stop()
        result(true)
    } else {
        result(FlutterMethodNotImplemented)
    }
    //result("iOS " + UIDevice.current.systemVersion)
  }

  public func start() {
   print("start loc")
   locationManager = CLLocationManager()
   locationManager?.delegate = self
   locationManager?.desiredAccuracy = kCLLocationAccuracyBest
   locationManager?.allowsBackgroundLocationUpdates = true
   locationManager?.showsBackgroundLocationIndicator = true
   locationManager?.requestWhenInUseAuthorization()
  }

  public func stop() {
   locationManager?.stopUpdatingLocation()
  }
  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        let timeInSeconds = location?.timestamp.timeIntervalSince1970 ?? 0.0
        let map = [
            "lat": NSNumber(value: location?.coordinate.latitude ?? 0),
            "lon": NSNumber(value: location?.coordinate.longitude ?? 0),
            "acc": NSNumber(value: location?.horizontalAccuracy ?? 0),
            "ele": NSNumber(value: location?.altitude ?? 0),
            "epoch": NSNumber(value: (Double(timeInSeconds)) * 1000.0) // in milliseconds since the epoch
        ]
        channel?.invokeMethod("onLocation", arguments: map)
    }
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("AUTH:")
        print(status)
        if status == .denied {
	   print("DENIED")
           startResult?(NSNumber(value: 0))
        } else if status == .authorized {
	   print("AUTHORIZED")
           startResult?(NSNumber(value: 1))
           locationManager?.startUpdatingLocation()
        } else if #available(macOS 10.12, *) {
            print("MACOS")
            if status == .authorizedAlways || status == .authorizedWhenInUse {
     	        print("ALWAYS")
                startResult?(NSNumber(value: 1))
                locationManager?.startUpdatingLocation()
            } else {
                startResult?(NSNumber(value:0))
            }
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
	    print("WHEN")
            startResult?(isHighAccuracyPermitted() ? NSNumber(value: 1) : NSNumber(value: 3))
            locationManager?.startUpdatingLocation()
        } else {
	    print("ELSE")
	    startResult?(NSNumber(value:0))
	}
	print("AUTH EXIT")
    }
    
    func isHighAccuracyPermitted() -> Bool {
        if (__IPHONE_14_0 != 0) {
        if #available(iOS 14.0, *) {
            let accuracy = locationManager?.accuracyAuthorization
            if accuracy == .reducedAccuracy {
                return false
            }
        }
        }
        return true
    }

}
