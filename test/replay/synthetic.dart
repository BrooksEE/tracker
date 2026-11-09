// Small made-up courses and runners, for tests that need no fixtures.
import 'dart:convert';
import 'dart:math' as math;

import 'fixture.dart';

const double _mPerDegLat = 111320.0;

/// An out-and-back: [legM] north from (lat0, lon0), turn, and back down a
/// parallel line [laneM] to the east. Course points every 100 m; the
/// turnaround point carries {"segment": true} when [marker] is set.
Map outAndBack({double legM = 2000, double laneM = 10, bool marker = true, double lat0 = 40, double lon0 = -105}) {
  double mPerDegLon = _mPerDegLat * math.cos(lat0 * math.pi / 180);
  List<Map> pts = [];
  int n = (legM / 100).round();
  for (int i = 0; i <= n; i++) {
    pts.add({"lat": lat0 + i * 100 / _mPerDegLat, "lon": lon0, "desc": ""});
  }
  if (marker) pts.last["desc"] = jsonEncode({"segment": true});
  for (int i = n; i >= 0; i--) {
    pts.add({"lat": lat0 + i * 100 / _mPerDegLat, "lon": lon0 + laneM / mPerDegLon, "desc": ""});
  }
  return {
    "name": "out and back",
    "lineOptions": {"strokeColor": "#FF0000", "strokeOpacity": 0.5},
    "points": pts,
  };
}

/// [path]'s points with each point's routed "directions" sub-points ahead of
/// it -- the line the Tracker and the app follow.
List<Map> expandedPoints(Map path) => [
      for (Map p in path["points"]) ...[...List<Map>.from(p["directions"] ?? const []), p]
    ];

/// A runner moving along [path] at [speed] m/s with a fix every [dt] s. Each
/// fix carries its true course distance (miles).
///
/// With [gpsM] > 0 the fixes get GPS error the way real receivers do: an
/// error of about [gpsM] meters per axis that drifts slowly (correlation time
/// [tauS] seconds) rather than jumping independently on every fix.
///
/// Like a real runner leaving the finish chute, it then mills about within
/// roughly [wanderM] meters of the finish for [postFinishS] seconds. (Warm-up
/// before the start is the warmUp condition, so it can apply to real tracks
/// too.)
List<Fix> runAlong(Map path,
    {double speed = 3,
    double dt = 2,
    double t0 = 1.7e9,
    double gpsM = 0,
    double tauS = 30,
    double postFinishS = 0,
    double wanderM = 40,
    int seed = 1}) {
  List<Map> pts = expandedPoints(path);
  List<double> cum = [0];
  for (int i = 1; i < pts.length; i++) {
    cum.add(cum.last + _meters(pts[i - 1], pts[i]));
  }
  math.Random rng = math.Random(seed);
  double gauss() => math.sqrt(-2 * math.log(1 - rng.nextDouble())) * math.cos(2 * math.pi * rng.nextDouble());
  double a = math.exp(-dt / tauS), b = math.sqrt(1 - a * a);
  double en = gauss() * gpsM, ee = gauss() * gpsM; // north / east error, meters
  double lat0 = (pts.first["lat"] as num).toDouble();
  double mPerDegLon = _mPerDegLat * math.cos(lat0 * math.pi / 180);

  List<Fix> out = [];
  int i = 1;
  void add(double epoch, double lat, double lon, double s) {
    out.add(Fix(epoch, lat + en / _mPerDegLat, lon + ee / mPerDegLon, gpsM > 0 ? gpsM : 5,
        truth: s / 1609.344, offM: 0));
    en = a * en + b * gauss() * gpsM;
    ee = a * ee + b * gauss() * gpsM;
  }

  for (double s = 0; s <= cum.last; s += speed * dt) {
    while (i < cum.length - 1 && cum[i] < s) {
      i++;
    }
    double f = cum[i] == cum[i - 1] ? 0 : (s - cum[i - 1]) / (cum[i] - cum[i - 1]);
    double lat = pts[i - 1]["lat"] + (pts[i]["lat"] - pts[i - 1]["lat"]) * f;
    double lon = pts[i - 1]["lon"] + (pts[i]["lon"] - pts[i - 1]["lon"]) * f;
    add(t0 + s / speed, lat, lon, s);
  }
  Map last = pts.last;
  add(out.last.epoch + dt, (last["lat"] as num).toDouble(), (last["lon"] as num).toDouble(), cum.last);
  for (Fix w in wanderAround((last["lat"] as num).toDouble(), (last["lon"] as num).toDouble(),
      start: out.last.epoch + dt, seconds: postFinishS, radiusM: wanderM, dt: dt, rng: rng)) {
    add(w.epoch, w.lat, w.lon, cum.last);
  }
  return out;
}

/// A fixture of one synthetic runner on [path].
Fixture syntheticFixture(String name, Map path, {double gpsM = 0, double postFinishS = 0, int seed = 1}) {
  List<Fix> fixes = runAlong(path, gpsM: gpsM, postFinishS: postFinishS, seed: seed);
  return Fixture(name, 0, 0, fixes.last.truth, [], path, [Track("t0", fixes, fixes.last.truth)]);
}

/// The standard synthetic runner the replay tests use: 3 m/s, a fix every
/// 2 s, 8 m drifting GPS error, 3 minutes about the finish afterwards.
Track syntheticRunner(Map path, int seed) {
  List<Fix> fixes = runAlong(path, gpsM: 8, postFinishS: 180, seed: seed);
  return Track("syn$seed", fixes, fixes.last.truth);
}

/// Fixes of someone milling about (warming up, waiting in a corral) within
/// roughly [radiusM] meters of (lat, lon) for [seconds], starting at [start].
/// Positions are exact; add GPS error separately if wanted.
List<Fix> wanderAround(double lat, double lon,
    {required double start, required double seconds, double radiusM = 80, double dt = 2, required math.Random rng}) {
  double gauss() => math.sqrt(-2 * math.log(1 - rng.nextDouble())) * math.cos(2 * math.pi * rng.nextDouble());
  double a = math.exp(-dt / 120), b = math.sqrt(1 - a * a);
  double mPerDegLon = _mPerDegLat * math.cos(lat * math.pi / 180);
  double n = 0, e = 0;
  return [
    for (double t = 0; t < seconds; t += dt)
      () {
        n = a * n + b * gauss() * radiusM;
        e = a * e + b * gauss() * radiusM;
        return Fix(start + t, lat + n / _mPerDegLat, lon + e / mPerDegLon, 8);
      }()
  ];
}

double _meters(Map a, Map b) {
  double rad(num d) => d * math.pi / 180;
  double c = math.sin(rad(a["lat"])) * math.sin(rad(b["lat"])) +
      math.cos(rad(a["lat"])) * math.cos(rad(b["lat"])) * math.cos(rad(b["lon"]) - rad(a["lon"]));
  return math.acos(c.clamp(-1.0, 1.0)) * 6371000;
}
