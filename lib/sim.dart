import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import "dart:async";
import "dart:io";
import 'package:cloud_firestore/cloud_firestore.dart';
import "tracker.dart";

class Simulator {
  bool running = false;

  void stop() {
    running = false;
  }

  Future<bool> start(Tracker tracker, Map coursePath) async {

    if(true) { // sim the route at a certain pace
      double pace = 4; // min/mile
      double skip = 0;
      List points = coursePath["points"];
      print("SIM0: ${points[0]}");
      print("SIM1: ${points[1]}");
      int idx = 0;
      print("SIM is starting");
      double startTime = DateTime.now().millisecondsSinceEpoch/1000.0 - (skip * 60) ;
      double distance=0;
      for (idx=0; idx < points.length; idx+=1) {
        if(coursePath["distances"][idx]/1.0 > skip) {
          break;
        } else {
          tracker.addPoint(LatLng(points[idx]["lat"], points[idx]["lon"]), coursePath["distances"][idx] * pace * 60 + startTime, 10, replay: true);
        }
      }
      if(idx == 0) {
        tracker.addPoint(LatLng(points[idx]["lat"], points[idx]["lon"]), startTime, 10);
      }
      running=true;
      int downsample=1;
      for (idx = idx+downsample; idx < points.length; idx+=downsample) {
        double epoch = (coursePath["distances"][idx] * pace * 60) + startTime;
        double dt = epoch - DateTime.now().millisecondsSinceEpoch/1000.0;
        print("SIM POINT: $idx, $dt");
        if(dt > 0) {
          await Future.delayed(Duration(milliseconds: (dt * 1000).toInt()), () => false);
        }
        tracker.addPoint(LatLng(points[idx]["lat"], points[idx]["lon"]), epoch, 10);
        if (!running) {
          print("SIM is exiting");
          return false;
        }
      }
      return true;

    } else {
      int skip = 0;//60*10;//(110*60).toInt();//1*3600 + 55*60;
      int speedup=2;

      List points = [];
      try {
        var data = await FirebaseFirestore.instance.doc("timing/tracking/archive/1684284").get();
        points = jsonDecode(AsciiDecoder().convert(GZipDecoder().decodeBytes(base64Decode(data["points"]))));
        print("SIM: $points");
        int idx = 0;
        double dt = 0;
        print("SIM is starting");
        double startTime = points[0]["epoch"]/1.0;
        for (idx=0; idx < points.length; idx+=1) {
          if(points[idx]["epoch"]/1.0 - startTime > skip) {
            break;
          } else {
            tracker.addPoint(LatLng(points[idx]["latM"]/1e6, points[idx]["lngM"]/1e6), points[idx]["epoch"]/1.0, points[idx]["accuracyK"]/1000, replay: true);
          }
        }
        if(idx == 0) {
          tracker.addPoint(LatLng(points[0]["latM"]/1e6, points[0]["lngM"]/1e6), DateTime.now().millisecondsSinceEpoch/1000, points[0]["accuracyK"]/1000);
        }
        running=true;
        int downsample=1;
        for (idx = idx+downsample; idx < points.length; idx+=downsample) {
          dt = (points[idx]["epoch"] - points[idx - downsample]["epoch"]) / speedup;
          print("POINT $idx $dt");
          await Future.delayed(Duration(milliseconds: (dt * 1000).toInt()), () => false);
          tracker.addPoint(LatLng(points[idx]["latM"]/1e6, points[idx]["lngM"]/1e6), DateTime.now().millisecondsSinceEpoch/1000, points[idx]["accuracyK"]/1000);
          if (!running) {
            print("SIM is exiting");
            return false;
          }
        }
        return true;
      } catch(e, stacktrace) {
        print("SIM ERROR: $e");
        print(stacktrace);
      }
    }
  }
}
