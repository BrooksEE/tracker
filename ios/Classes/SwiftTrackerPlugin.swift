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
    } else if(call.method == "progressStart" || call.method == "progressUpdate" || call.method == "progressEnd") {
        // Race progress Live Activity (iOS 16.2+); older iOS ignores these.
        // See oyo/docs/race-progress-notification.md.
        if #available(iOS 16.2, *) {
            handleProgress(call)
        }
        result(nil)
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
   // Don't let iOS pause updates while the participant stands still (e.g. in
   // the corral): a pause suspends the app, freezing tracking and the Live
   // Activity until it's opened.
   locationManager?.pausesLocationUpdatesAutomatically = false
   locationManager?.activityType = .fitness
   locationManager?.requestWhenInUseAuthorization()
  }

  public func stop() {
   locationManager?.stopUpdatingLocation()
  }
  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // locations is oldest first; when iOS batches fixes (it does in the
        // background) the newest one is the last.
        let location = locations.last
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
    
    // MARK: Race progress Live Activity

    @available(iOS 16.2, *)
    private func handleProgress(_ call: FlutterMethodCall) {
        #if canImport(ActivityKit)
        guard let args = call.arguments as? [String: Any],
              let token = args["token"] as? String else { return }
        let stateMap = args["state"] as? [String: Any] ?? [:]
        let state = Self.contentState(stateMap)
        let controller = RaceProgressController.shared
        switch call.method {
        case "progressStart":
            let attributes = RaceProgressAttributes(
                token: token,
                title: args["title"] as? String ?? "",
                units: stateMap["units"] as? String ?? "mi",
                primaryColor: (args["primaryColor"] as? NSNumber)?.intValue,
                secondaryColor: (args["secondaryColor"] as? NSNumber)?.intValue)
            controller.start(token: token, attributes: attributes, state: state)
        case "progressUpdate":
            controller.update(token: token, state: state,
                              reshow: args["reshow"] as? Bool ?? false)
        case "progressEnd":
            controller.end(token: token, state: state,
                           finished: args["finished"] as? Bool ?? false,
                           resultText: args["text"] as? String ?? "")
        default:
            break
        }
        #endif
    }

    #if canImport(ActivityKit)
    /// The `TrackerProgress.toMap()` map from Dart.
    @available(iOS 16.2, *)
    private static func contentState(_ m: [String: Any]) -> RaceProgressAttributes.ContentState {
        func double(_ key: String) -> Double? { (m[key] as? NSNumber)?.doubleValue }
        return RaceProgressAttributes.ContentState(
            distance: double("distance") ?? 0,
            total: double("total"),
            startDate: double("startEpoch").map { Date(timeIntervalSince1970: $0) },
            pace: m["pace"] as? String,
            status: m["status"] as? String,
            text: m["text"] as? String ?? "",
            finished: false,
            resultText: nil)
    }
    #endif

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
