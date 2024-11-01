import 'dart:convert';
import 'package:convert/convert.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:db/db.dart';
import 'package:db/RPC.dart';
import 'package:db/dialogs.dart' as dlg;
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:convert';
import "dart:io";
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sim.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pth;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:crypto/crypto.dart';
//import 'package:sensors/sensors.dart';
//import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

enum UNITS {
  IMPERIAL,
  SI,
}

CollectionReference? _pntsCollection = null;
CollectionReference? _imuCollection = null;
DocumentReference? _locRef = null;
double _lastPointsEpoch = 0;
int OFF_COURSE_COUNT_THRESHOLD = 15;
double THRESHOLD_OFF_COURSE = 70;
double THRESHOLD_MATCH_LOWER_BOUND = 100;
double THRESHOLD_MATCH_UPPER_BOUND = 200;

Color hexToColor(double opacity, String hexString) {
  assert(0 <= opacity && opacity <= 1, 'Opacity must be between 0 and 1');
  assert(hexString.length == 7 && hexString.startsWith('#'), 'Hex string must be 7 characters, starting with "#"');

  // Convert opacity to a 2-digit hex value
  final alpha = (opacity * 255).toInt().toRadixString(16).padLeft(2, '0');
  final hexColor = hexString.replaceFirst('#', '');

  return Color(int.parse(alpha + hexColor, radix: 16));
}
class Location {
  late LatLng latLng;
  late double epoch;
  late double accuracy;

  Location({required this.latLng, required this.epoch, required this.accuracy});
  Location.fromJson(Map<dynamic, dynamic> j) {
    epoch = j['epoch'] / 1000.0;
    accuracy = j['acc'];
    latLng = LatLng(j['lat'], j['lon']);
  }
  String toString() {
    return "lat=${latLng.latitude} lon=${latLng.longitude} epoch=${epoch}";
  }
}

enum EVENT_TYPE {
  /// Races cannot be paused. There is one start and one stop time
  RACE,
  /// Runs can be paused and have a list of start/stop times
  RUN,
}


class Tracker {
  static const int EARTH_RADIUS_METERS = 6371000;
  static const double METERS_PER_MILE = 1609.344;
  static const double METERS_PER_KM = 10000;

  Participant? participant;
  UNITS units = UNITS.IMPERIAL;
  late Set<Polyline> polylines;
  late Polyline myLine;
  late Polyline myLineFixed;
  Polyline? course;
  //Marker? lastPosMarker;
  LatLng? lastPos;
  List<Watcher> watchers = [];
  double prevDist = 0;
  String deviceId;

  int segIdx = 0;
  int posIdx = 0; // index in course of current position.
  double distance = 0;
  List<double>? distances;
  Map? coursePath;
  Map completeCourse = {};
  List segments = [];
  double prevSeconds = 0;
  List timingPoints = [];
  bool stateNearLastPointOfSegment = false;
  int offCourse = 0;
  bool offCourseWarning = false;
  Function? onOffCourse;
  Function(double)? onMatchedNewLocation;
  Function(double)? onBackOnCourse;
  Function(Location)? onLocation;
  Function(Location, double, Map?, bool, double?)? onPathUpdate;
  Function? onPathCompleted;
  Simulator? simulator;
  String? fireStorePointsPath, fireStoreImuPath;
  String? fireStoreStatusPath;

  static const MethodChannel _channel = const MethodChannel('tracker');

  static Future<void> startLocServices({required String title, required String text, required Function cb}) async {
    _channel.setMethodCallHandler((MethodCall call) async {
        if(call.method == "onLocation") {
          Location loc;
          Map locMap;
          try {
            if(call.arguments is String) {
              locMap = jsonDecode(call.arguments);
            } else if(call.arguments is Map) {
              locMap = Map<dynamic, dynamic>.from(call.arguments);
            } else {
              print("Unknown loc type");
              return;
            }
            loc = Location.fromJson(locMap);
          } catch(e) {
            print(e);
            return;
          }
          cb(loc);
        }
    });
    var r = await _channel.invokeMethod('start', {"title": title, "text": text});
    print("START $r");
  }

  static Future<void> stopLocServices() async {
    print("STOPPING LOC SERVICES");
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('stop');
  }

  bool fireStoreSync;
  bool sim;
  EVENT_TYPE eventType;
  int maxCourseTimeHours;
  /// list of event start/stop times as milliseoncds since epoch
  List<int> times = [];
  /// Title of app as displayed in notification window
  String appTitle;
  int pid, eid, uid; //participant id, event id, user id
  static StreamSubscription? subscriptionAccel, subscriptionGyro;

  Tracker({
    required this.pid,
    required this.eid,
    required this.uid,
    required this.eventType,
    required this.appTitle,
    required this.deviceId,
    this.fireStoreSync: false,
    this.fireStorePointsPath: null,
    this.fireStoreStatusPath: null,
    this.fireStoreImuPath: null,
    this.sim          : false,
    this.maxCourseTimeHours: 10,
    this.coursePath   : null,
    timingPoints : null,
    this.onOffCourse  : null,
    this.onMatchedNewLocation : null,
    this.onBackOnCourse : null,
    this.onLocation: null,
    this.onPathUpdate: null,
    this.onPathCompleted: null,
  }) {
    //_channel.setMethodCallHandler((MethodCall call) async {
    //  if(call.method == "setLocation") {
    //    print("setLocation called ${call.arguments}");
    //    Map args = call.arguments;
    //    addPoint(Location(latLng: LatLng(args["lat"], args["lon"]), epoch: args["epoch"], accuracy: args["accuracy"]));
    //  }
    //});
    times.clear();
    // only keep timingpoints which have devices starting the the nane "PHONE"
    offCourse = 0;
    watchers.clear();
    prevDist = 0;
    prevSeconds = 0;
    offCourseWarning = false;

    if(timingPoints != null) {
      for (var idx = 0; idx < timingPoints.length; idx++) {
        Map tp = timingPoints[idx];
        for (var idx2 = 0; idx2 < tp["devices"].length; idx2++) {
          String dev = tp["devices"][idx2];
          if (dev.startsWith("PHONE")) {
            this.timingPoints.add(tp);
// star            tp["device"] = dev;
          }
        }
      }
    } else {
      this.timingPoints = [];
    }

    polylines = Set<Polyline>();

    if(coursePath != null) {
      print("TIMING POINTS=$timingPoints");
      print(coursePath);
      print("Length point 0=${coursePath!["points"].length}");

      // insert the directions between each point
      List points = [];
      for (int idx = 0; idx < coursePath!["points"].length; idx++) {
        Map cp = coursePath!["points"][idx];
        if (cp.containsKey("directions")) {
          for (int idx2 = 0; idx2 < cp["directions"].length; idx2++) {
            var cp2 = cp["directions"][idx2];
            points.add(cp2);
            //print("  cp2[${idx2}]: ${cp2['lat']} ${cp2['lon']}");
          }
          cp.remove("directions");
        }
        //print("cp[${idx}]: ${cp['lat']} ${cp['lon']}");
        points.add(cp);
      }
      coursePath!["points"] = points;
      print("Length point 1=${coursePath!["points"].length}");

      late Color courseColor;
      try {
        if(coursePath != null) {
          courseColor = hexToColor(coursePath?["lineOptions"]["strokeOpacity"], coursePath?["lineOptions"]["strokeColor"]);
        }
      } catch(e) {
        courseColor = Color.fromARGB(128, 255, 90, 90);
      }

      course = Polyline(
        polylineId: PolylineId("1"),
        color: courseColor,
        width: 10,
        zIndex: 1,
        points: toPoints(coursePath!),
      );

      // insert interpolation points now to ensure any large gaps between points
      // don't cause jumping issues with aligment. Do this after creating the
      // 'drawing' of the route for the map preview because interpolation
      // will not add any value to the map preview.
      List points2 = [];
      double min_dx_meters = 10;
      for (var idx = 0; idx < points.length - 1; idx++) {
        points2.add(points[idx]); // insert current point
        // calc distance between current point and next point
            double dx = distanceMeters(LatLng(points[idx]["lat"], points[idx]["lon"]),
            LatLng(points[idx + 1]["lat"], points[idx + 1]["lon"]));
        // calc how many points need inserted between to ensure the min distance between points is met
        int N = (dx / min_dx_meters).floor();
        for (var idx2 = 0; idx2 < N; idx2++) {
          Map p0 = points[idx];
          Map p1 = points[idx + 1];
          Map p = {
            "lat": p0["lat"] + (p1["lat"] - p0["lat"]) * (idx2 + 1) / (N + 1),
            "lon": p0["lon"] + (p1["lon"] - p0["lon"]) * (idx2 + 1) / (N + 1)
          };
          points2.add(p);
        }
      }
      if (points2.length > 0) {
        // the last point that is not added by the previous algorithm
        points2.add(points[points.length - 1]);
      }
      coursePath!["points"] = points2;
      print("Length point 2=${coursePath!["points"].length}");

      posIdx = -1;
      segIdx = 0;
      stateNearLastPointOfSegment = false;
      myLineFixed = Polyline(
        polylineId: PolylineId("2"),
        color: Color.fromARGB(128, 128, 255, 255),
        width: 2,
        points: [],
        zIndex: 2,
      );
      //polylines.add(myLine);
      polylines.add(course!);
      polylines.add(myLineFixed);
      distances = distancesMeters(toPoints(coursePath!));
      coursePath!["distances"] = distances;
      segmentCourse();
      print("Created ${segments.length} segments");
    }

    distance = 0;
    myLine = Polyline(
      polylineId: PolylineId("0"),
      color: Color.fromARGB(192, 128, 128, 255),
      width: 4,
      points: [],
      zIndex: 2,
    );

    _lastPointsEpoch = 0;
    if(fireStorePointsPath != null) {
      _pntsCollection = FirebaseFirestore.instance.collection(fireStorePointsPath!);
    } else {
      _pntsCollection = null;
    }
    if(fireStoreStatusPath != null) {
      _locRef  = FirebaseFirestore.instance.doc(fireStoreStatusPath!);
    } else {
      _locRef = null;
    }
    if(false) {
      subscriptionGyro?.cancel();
      subscriptionGyro = null;
      subscriptionAccel?.cancel();
      subscriptionAccel = null;
      if(fireStoreImuPath != null) {
        /*
        _imuCollection = FirebaseFirestore.instance.collection(fireStoreImuPath);
        subscriptionAccel = accelerometerEvents.listen((AccelerometerEvent event) {
          _imuCollection.add({"e":DateTime.now().millisecondsSinceEpoch, "x": event.x, "y": event.y, "z": event.z, "type":"a"});
        });
        */
        // [AccelerometerEvent (x: 0.0, y: 9.8, z: 0.0)]

        //userAccelerometerEvents.listen((UserAccelerometerEvent event) {
        //  print(event);
        //});
        // [UserAccelerometerEvent (x: 0.0, y: 0.0, z: 0.0)]
        /*
        subscriptionGyro = gyroscopeEvents.listen((GyroscopeEvent event) {
          _imuCollection.add({"e":DateTime.now().millisecondsSinceEpoch, "x": event.x, "y": event.y, "z": event.z, "type":"g"});
        });
         */
      } else {
        _imuCollection = null;
        subscriptionAccel = null;
        subscriptionGyro = null;
      }
    }
  }

  void dispose() {
    subscriptionAccel?.cancel();
    subscriptionGyro?.cancel();
  }

  List<LatLng> toPoints(Map path) {
    List<LatLng> points = <LatLng>[];
    for (int idx = 0; idx < path["points"].length; idx++) {
      var pt = path["points"][idx];
      double lat = pt["lat"];
      double lng = pt["lon"];
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  Future<void> start() async {
    times.add(DateTime.now().millisecondsSinceEpoch);
    print("SIM: ${sim}");
    if(sim) {
      if(coursePath != null) {
        simulator = Simulator();
        simulator?.start(this, coursePath!);
      }
    } else {
//      await _start();

      PermissionStatus status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        await startLocServices(
          title: appTitle,
          text: "Tracking your race",
          cb: (Location loc) {
            print("${loc}");
            addPoint(loc);
          });
      } else {
        throw Exception("PERMISSION_DENIED");
      }
    }
  }
/*
  Future<void> _setLoc(bg.Location loc) async {
    Location location = Location(
      latLng: LatLng(loc.coords.latitude, loc.coords.longitude),
      epoch: DateTime.parse(loc.timestamp).millisecondsSinceEpoch / 1000,
      accuracy: loc.coords.accuracy);
    await addPoint(location);
  }
*/
  /*
  Future<void> _start() async {
    // Fired whenever a location is recorded
    bg.BackgroundGeolocation.onLocation((bg.Location loc) {
      print('[location] - $loc');
      _setLoc(loc);
    });

    bg.BackgroundGeolocation.onHeartbeat((bg.HeartbeatEvent event) {
      print('[heartbeat] - $event');
      bg.BackgroundGeolocation.getCurrentPosition(samples: 1, persist: true)
          .then((loc) {
        print('[loc] - $loc');
        _setLoc(loc);
      });
    });

    // Fired whenever the plugin changes motion-state (stationary->moving and vice-versa)
    bg.BackgroundGeolocation.onMotionChange((bg.Location loc) {
      print('[motionchange] - $loc');
      _setLoc(loc);
    });

    // Fired whenever the state of location-services changes.  Always fired at boot
    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      print('[providerchange] - $event');
    });

    bg.State state = await bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 1.0,
      stopOnTerminate: true,
      disableStopDetection: true,
      pausesLocationUpdatesAutomatically: false,
      startOnBoot: false,
      debug: false,
      locationAuthorizationRequest: "WhenInUse",
      reset: true,
      heartbeatInterval: 60,
      //preventSuspend: true, // removed because "WhenInUse" renders this useless
      isMoving: true,
      stopAfterElapsedMinutes: (60.0 * maxCourseTimeHours).round(), // automatically stop if not done in time
      logLevel: bg.Config.LOG_LEVEL_VERBOSE,
      activityType: bg.Config.ACTIVITY_TYPE_OTHER_NAVIGATION, // don't jump to roads
      foregroundService: true, // android only
      notification: bg.Notification( // android only
          title: appTitle,
          text: "Tracking your race"),
    ));
    print("TRACKER: bg_state=" + state.toString());
    if (!state.enabled) {
      print("TRACKER: STARTING BackgroundGeolocation");
      bg.BackgroundGeolocation.start();
    }
  }
*/

  Future<void> stop() async {
    times.add(DateTime.now().millisecondsSinceEpoch);
    subscriptionAccel?.cancel();
    subscriptionGyro?.cancel();
    if(sim) {
      simulator?.stop();
    } else {
      await stopLocServices();
    }
  }

  bool trackThisPoint(LatLng latLng) {
    List p = findClosestPoint(completeCourse["latlngs"], latLng);
    double dist = p[1];
    if(dist < 200) {
      return true;
    } else {
      return false;
    }
  }

  void addPoint(Location location, {replay = false}) {
    LatLng latLng = location.latLng;
    if(!replay && trackThisPoint(latLng)) {
      Map<String, dynamic> latLng_ = {
        "accuracyK": (location.accuracy*1000).toInt(),
        "dev_id": deviceId,
        "epoch": location.epoch,
        "latM": (latLng.latitude * 1e6).toInt(),
        "lngM": (latLng.longitude * 1e6).toInt(),
        "distK": (distance*1e3).toInt(),
        "loc" : GeoPoint(latLng.latitude, latLng.longitude),
        "pid" : pid,
        "eid" : eid,
      };
      if(_pntsCollection != null) {
        _pntsCollection!.add(latLng_).then((ref) {}, onError: (e) {
          print("exception writing point: ${e}");
        });
      }
      if(_locRef != null && latLng_["epoch"] - _lastPointsEpoch >= 5) {
        _locRef!.set({"location": latLng_}, SetOptions(merge: true)).then((ref) {}, onError: (e) {
          print("exception writing location: ${e}");
        });
        _lastPointsEpoch = latLng_["epoch"];
      }
    }
    myLine.points.add(latLng);
    if(onLocation != null) {
      onLocation!(location);
    }

    if (location.accuracy > 50) {
      lastPos = latLng;
      return; // don't use a noisy point
    }

    if(segments.length == 0) {
      if(lastPos != null) {
        distance += distanceMeters(latLng, lastPos!);
      }
      if(onPathUpdate != null) {
        onPathUpdate!(location, distance, null, replay, null);
      }
      lastPos = latLng;
      return;
    }

    Map seg = segments[segIdx];
    lastPos = latLng;

    // check if we are close to the end of this segment. Once we enter the
    // bubble of being within 50m (or THRESHOLD_IN_BUBBLE) of the end of the segment, then we will
    // automatically advance to the next segment if the distance from the end
    // of the segment grows to more than 100m (or THRESHOLD_OUT_OF_BUBBLE) and in the BUBBLE of the next segment.
    double THRESHOLD_IN_BUBBLE = 40;
    double THRESHOLD_OUT_OF_BUBBLE = 2 * THRESHOLD_IN_BUBBLE;
    if (seg["latlngs"].length > 0 && segIdx < segments.length - 1) {
      double distToLastPointInSegment =
      distanceMeters(latLng, seg["latlngs"][seg["latlngs"].length - 1]);
      print(
          "distToLastPointInSegment=$distToLastPointInSegment  statstateNearLastPointOfSegment=$stateNearLastPointOfSegment");
      if (stateNearLastPointOfSegment) {
        if (distToLastPointInSegment > THRESHOLD_OUT_OF_BUBBLE) {
          List y = findClosestPoint(segments[segIdx + 1]["latlngs"], latLng);
          print("distance To next Segment= ${y[1]}");
          if (y[1] < THRESHOLD_IN_BUBBLE) {
            advanceToNextSegment();
            seg = segments[segIdx];
          }
        }
      } else if (distToLastPointInSegment < THRESHOLD_IN_BUBBLE) {
        stateNearLastPointOfSegment = true;
      }
    }

    List x = findClosestPoint(seg["latlngs"], latLng, posIdx < 0 ? 0 : posIdx);
    double dist = x[1];
    int newPosIdx = x[0];

    if (dist > THRESHOLD_OFF_COURSE) {
      offCourse++;
      print("OFF COURSE COUNT $offCourse  WATCHERS=${watchers.length}");
      if(offCourse < OFF_COURSE_COUNT_THRESHOLD) {
        print("Waiting for more off course points");
      } else if(offCourse == OFF_COURSE_COUNT_THRESHOLD || watchers.length == 0) {
        // first look forward for potential matching points
        for(int sIdx = segIdx; sIdx<segments.length; sIdx++) {
          List x = findClosestPoint(segments[sIdx]["latlngs"], latLng, 0);
          double dist2 = x[1];
          int pIdx = x[0];
          if(dist2 <= THRESHOLD_OFF_COURSE) {
            watchers.add(Watcher(sIdx, pIdx, segments[sIdx]));
          } else {
            print("NO WATCHER for SEG=${sIdx}  dist2=${dist2}");
          }
        }
        // second look backward for potential matching points
        for(int sIdx = segIdx; sIdx>= 0; sIdx--) {
          List x = findClosestPoint(segments[sIdx]["latlngs"], latLng, 0);
          double dist2 = x[1];
          int pIdx = x[0];
          if(dist2 <= THRESHOLD_OFF_COURSE) {
            watchers.add(Watcher(sIdx, pIdx, segments[sIdx]));
          } else {
            print("NO WATCHER for SEG=${sIdx}  dist2=${dist2}");
          }
        }
        if(watchers.length == 0) {
          print("  REPLAY=${replay} ofoffCourseWarning=${offCourseWarning}");
          if(!replay && !offCourseWarning) {
            offCourseWarning = true;
            if(onOffCourse != null) {
              onOffCourse!();
            }
          }
        }
      } else {
        for(int idx=0; idx<watchers.length; idx++) {
          Watcher watcher = watchers[idx];
          int pIdx = watcher.addPoint(latLng);
          if(pIdx >= 0) {
            double newDist = (segments[watcher.segIdx]["distances"][pIdx] * 10).round() / 10.0;
            if(!replay) {
              if(onMatchedNewLocation != null) {
                onMatchedNewLocation!(newDist);
              }
            }
            set_distance(newDist);
            return;
          }
        }
        watchers.removeWhere((w) => w.noMatch);
      }
      return; // too far from course
    }
    watchers.clear();
    offCourse = 0;
    if(offCourseWarning) {
      offCourseWarning = false;
      if(!replay) {
        if(onBackOnCourse != null) {
          onBackOnCourse!(distance);
        }
      }
    }

    while (posIdx < newPosIdx) {
      posIdx++;
      distance = seg["distances"][posIdx];
      myLineFixed.points.add(seg["latlngs"][posIdx]);
      Map p = seg["points"][posIdx];
      if(onPathUpdate != null && distances != null) {
        onPathUpdate!(location, distance, p, replay, distances![distances!.length-1]);
      }
    }
    print("posIdx=$posIdx newPosIdx=$newPosIdx");
    print(" segIdx=$segIdx posIdx=$posIdx distance=$distance");
    if (posIdx == seg["points"].length - 1) {
      advanceToNextSegment();
    }
  }

  bool alreadyCalledOnPathCompleted = false;
  void advanceToNextSegment() {
    stateNearLastPointOfSegment = false;
    if(segIdx+1 < segments.length) {
      segIdx += 1;
      posIdx = -1;
      alreadyCalledOnPathCompleted = false;
    } else {
      if(onPathCompleted != null && !alreadyCalledOnPathCompleted) {
        alreadyCalledOnPathCompleted = true;
        try {
          onPathCompleted!();
        } catch(e) {
          print("onPathCompleted failed: $e");
        }
      }
    }
  }

  void segmentCourse() {
    if(coursePath == null || distances == null) {
      return;
    }
    print("COURSE POINTS LENGTH: ${coursePath!['points'].length}");
    Map seg = {
      "offset": 0,
      "points": <Map>[],
      "latlngs": <LatLng>[],
      "distances": <double>[],
      "indexs": <int>[],
    };
    segments.add(seg);
    completeCourse = {
      "offset": 0,
      "points": <Map>[],
      "latlngs": <LatLng>[],
      "distances": <double>[],
      "indexs": <int>[],
    };
    List points = coursePath!["points"];
    for (int idx = 0; idx < points.length; idx++) {
      Map p = points[idx];
      Map<String, dynamic> data = {"idx": idx};
      if (p.containsKey("desc")) {
        String desc = p["desc"];
        if (desc != null && desc.trim() != "") {
          try {
            data.addAll(jsonDecode(desc.trim()));
            print("$idx: $data");
          } catch (error) {
            print("error decoding $desc: $error");
          }
        }
      }
      p["data"] = data;
      seg["points"].add(p);
      seg["latlngs"].add(LatLng(p["lat"], p["lon"]));
      seg["distances"].add(distances![idx]);
      seg["indexs"].add(idx);
      completeCourse["points"].add(p);
      completeCourse["latlngs"].add(LatLng(p["lat"], p["lon"]));
      completeCourse["distances"].add(distances![idx]);
      completeCourse["indexs"].add(idx);
      if (data.containsKey("segment")) {
        seg = {
          "offset": distances![idx],
          "points": <Map>[
            {"lat": p["lat"], "lon": p["lon"]}
          ],
          "latlngs": <LatLng>[LatLng(p["lat"], p["lon"])],
          "distances": <double>[distances![idx]],
          "indexs": <int>[idx],
        };
        segments.add(seg);
      }
    }
    //print(segments[1]["distances"]);
  }

  static List findClosestPoint(List<LatLng> points, LatLng p,
      [int starting_pos = 0]) {
    double min = double.maxFinite;
    int min_idx = -1;
    for (int idx = starting_pos; idx < points.length; idx++) {
      double d = distanceMeters(points[idx], p);
      if (d < min) {
        min_idx = idx;
        min = d;
      }
    }
    return [min_idx, min];
  }

  void set_distance(double dist) {
    segIdx = 0;
    posIdx = 0;
    distance = 0;
    offCourse = 0;
    offCourseWarning = false;
    prevDist = 0;
    prevSeconds = 0;
    myLineFixed.points.clear();
    //myLine.points.clear();
    int sIdx = 0, pIdx=0;
    // now replay the points until distance == dist
    while(distance < dist) {
      while(distance < dist) {
        LatLng latLng = segments[sIdx]["latlngs"][pIdx];
        Location location = Location(latLng: latLng, epoch: 0, accuracy: 0);
        addPoint(location, replay: true);
        pIdx++;
        if(pIdx >= segments[sIdx]["points"].length) {
          sIdx++;
          pIdx = 0;
        }
      }
      if(segIdx >= segments.length) {
        break;
      }
    }
  }

  double getDistanceMeters() {
    return (units == UNITS.IMPERIAL) ? distance * 1609.443 : distance * 1000;
  }

  Future<void> replayHistory() async {
    print("HISTORY: ENTRY");
    if(_pntsCollection == null) { return; }
    try {
      QuerySnapshot snapshot = await _pntsCollection!.where("pid",isEqualTo: pid).orderBy('epoch').get();
      snapshot.docs.forEach((QueryDocumentSnapshot s) {
        Map p = s.data() as Map;
        print("HISTORY: $p");
        LatLng latLng = LatLng(p["latM"] / 1e6, p["lngM"] / 1e6);
        Location location = Location(latLng: latLng, epoch: p["epoch"]/1.0, accuracy: p["accuracyK"] / 1000.0);
        addPoint(location, replay: true);
      });
    } catch(e, stacktrace) {
      print("REPLAY HISTORY ERR: ${e.toString()}");
      print(stacktrace);
    }
  }

  List<double> distancesMeters(List<LatLng> points) {
    // returns a List of distance in meters for the provided points List
    List<double> d = [0.0];
    double cum = 0;
    for (int idx = 1; idx < points.length; idx++) {
      cum += distanceMeters(points[idx], points[idx - 1]) /
          ((units == UNITS.IMPERIAL) ? METERS_PER_MILE : METERS_PER_KM);
      d.add(cum);
    }
    return d;
  }

  static double distanceMeters(LatLng p1, LatLng p2) {
    double lat1 = p1.latitude / 180.0 * math.pi;
    double lon1 = p1.longitude / 180.0 * math.pi;
    double lat2 = p2.latitude / 180.0 * math.pi;
    double lon2 = p2.longitude / 180.0 * math.pi;
    return math.acos(math.sin(lat1) * math.sin(lat2) +
        math.cos(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)) *
        EARTH_RADIUS_METERS;
  }


}

class Watcher {
  int segIdx;
  int posIdx;
  Map seg;
  double accum = 0;
  bool noMatch = false;
  Watcher(this.segIdx, this.posIdx, this.seg) {
    accum = 0;
    noMatch = false;
    print("  CREATED WATCHER FOR SEG ${segIdx} at ${posIdx}");
  }

  int addPoint(LatLng loc) {
    // returns -1 if still watching. otherwise returns posIdx at the point of matching. throws a WatcherDoesNotMatch if not a match.
    if(noMatch) {
      return -1;
    }
    List x = Tracker.findClosestPoint(seg["latlngs"], loc, posIdx);
    double dist = x[1];
    int newPosIdx = x[0];
    if(dist > THRESHOLD_OFF_COURSE) {
      print("  NO MATCHED DUE TO OFF SEGMENT IN SEG ${segIdx} at ${posIdx}");
      noMatch = true;
      return -1;
    }
    while (posIdx < newPosIdx) {
      posIdx++;
      if(posIdx >= seg["latlngs"].length) {
        noMatch = true;
        return -1;
      }
      accum += Tracker.distanceMeters(seg["latlngs"][posIdx-1], seg["latlngs"][posIdx]);
      if(accum > THRESHOLD_MATCH_LOWER_BOUND && accum < THRESHOLD_MATCH_UPPER_BOUND) {
        print("  MATCHED NEW LOCATION IN SEG ${segIdx} at ${posIdx}");
        return posIdx;
      }
      if(accum > THRESHOLD_MATCH_UPPER_BOUND) {
        print("  NO MATCHED DUE TO BEYOND UPPER BOUND IN SEG ${segIdx} at ${posIdx}");
        noMatch = true;
        return -1;
      }
    }
    print("  STILL MATCHING SEG ${segIdx} at ${posIdx}");
    return -1; // still watching
  }
}

Future<Uint8List?> getBytesFromAsset(String path, int width) async {
  ByteData data = await rootBundle.load(path);
  ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
  ui.FrameInfo fi = await codec.getNextFrame();
  return (await fi.image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
}


String dt2elapsed(double dt) {
  int h = (dt / 3600).floor();
  int m = ((dt - 3600 * h) / 60).floor();
  int s = (dt - 3600 * h - 60 * m).floor();
  return "$h:${(m < 10) ? "0" : ""}$m:${(s < 10) ? "0" : ""}$s";
}

String pace2str(double dt) {
  int m = (dt / 60).floor();
  int s = (dt - 60 * m).floor();
  return "${m < 10 ? "0" : ""}$m:${s < 10 ? "0" : ""}$s";
}


class RaceData {
  Map? raceData;
  Race race;

  RaceData(this.race);

  dynamic? get(String key) {
    if(raceData?[key] != null) {
      return raceData![key];
    }
    return null;
  }

  Future<void> sync({
    Function? success=null,
  }) async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String? url = race.url_app_data;
    print("DOWNLOAD URL: ${url}");
    if (url == null || url.isEmpty) {
      raceData = null;
    } else {
      List p = url.split("/");
      String fname = p[p.length - 1];
      fname = fname.replaceAll(" ", "");
      File file = File(pth.join(appDocDir.path, fname));

      int retry=10;
      while(!await file.exists() || !await shaCheck(file)) {
        try {
          await RPC().fileDownload(url, fname);
        } catch(e) {
          print("fileDownload url=${url} retry=${retry} error=${e}");
        }
        retry--;
        if(retry < 0) {
          return;
        }
      }
      final destinationDir = Directory(pth.join(appDocDir.path, "race_data"));
      if(await destinationDir.exists()) {
        await destinationDir.delete(recursive: true);
      }
      int t0 = DateTime.now().millisecondsSinceEpoch;
      try {
        await ZipFile.extractToDirectory(zipFile: file, destinationDir: destinationDir);
      } catch (e) {
        print(e);
      }
      int t1 = DateTime.now().millisecondsSinceEpoch;
      print("Unzip took ${t1-t0} seconds.");
      File dataFile = File(pth.join(destinationDir.path, "data.json"));
      if(! await dataFile.exists()) {
        dlg.showError("Error: Race data file does not exist");
      } else {
        raceData = jsonDecode(await dataFile.readAsString());
        raceData!["path"] = destinationDir.path;
        print("TUT: ${raceData!["instructions"]}");
        print("PATHS: ${raceData!["paths"]}");
      }
    }
    if(success != null) {
      success();
    }
  }

  Future<bool> shaCheck(File file)  async {
    Digest fdigest = await sha1.bind(file.openRead()).first;
    String sha1sumA = hex.encode(fdigest.bytes);
    String sha1sumB = file.path.split("_").last.split(".")[0];
    print("SHA1SUMA: $sha1sumA");
    print("SHA1SUMB: $sha1sumB");
    return sha1sumA == sha1sumB;
  }
}

Future<Map> get_mapp(int id, BuildContext context) async {
  return await RPC()
      .rpc("gmaps", "Mapp", "get", {"id": id}, "Fetching Map...");
}

Future<Map> get_from_path(int id) async {
  return await RPC().rpc("gmaps", "Mapp", "get_from_path", {"id": id}, "Fetching Map...");
}

List<LatLng> toPoints(Map path) {
  List<LatLng> points = <LatLng>[];
  for (int idx = 0; idx < path["points"].length; idx++) {
    var pt = path["points"][idx];
    double lat = pt["lat"];
    double lng = pt["lon"];
    points.add(LatLng(lat, lng));
  }
  return points;
}
