// Conditions: ways to perturb a real course or a real track so one recording
// tests many situations. Each fix keeps its reference (truth) position, so
// results stay comparable to the unperturbed run.
import 'dart:convert';
import 'dart:math' as math;

import 'fixture.dart';
import 'synthetic.dart';

typedef CourseTransform = Map Function(Map path);
typedef FixTransform = List<Fix> Function(List<Fix> fixes, double courseMi, math.Random rng);

/// Something done to the tracker part-way through the run, at the first fix
/// whose reference position reaches [atFraction] of the course.
class Action {
  final String kind; // "restart" | "set_distance"
  final double atFraction;
  const Action(this.kind, this.atFraction);
}

class Condition {
  final String name;
  final String description;
  final List<CourseTransform> course;
  final List<FixTransform> fixes;
  final List<Action> actions;
  const Condition(this.name, this.description,
      {this.course = const [], this.fixes = const [], this.actions = const []});

  /// Both conditions applied together, e.g. noSegments + gpsGap.
  Condition operator +(Condition o) => Condition("$name+${o.name}", "$description; ${o.description}",
      course: [...course, ...o.course], fixes: [...fixes, ...o.fixes], actions: [...actions, ...o.actions]);
}

// ------------------------------------------------------------ course transforms

/// Remove every {"segment": ...} marker, as if the timer forgot them.
Map stripSegments(Map path) {
  for (Map p in path["points"]) {
    String desc = (p["desc"] ?? "").toString().trim();
    if (desc.isEmpty) continue;
    try {
      var data = jsonDecode(desc);
      if (data is Map && data.containsKey("segment")) {
        data.remove("segment");
        p["desc"] = data.isEmpty ? "" : jsonEncode(data);
      }
    } catch (_) {}
  }
  return path;
}

// --------------------------------------------------------------- fix transforms

int _firstAt(List<Fix> fixes, double mi) {
  for (int i = 0; i < fixes.length; i++) {
    if (fixes[i].truth >= mi) return i;
  }
  return fixes.length;
}

/// Drop every fix before the runner reached [fraction] of the course: the app
/// was opened mid-race.
FixTransform lateStart(double fraction) =>
    (fixes, courseMi, rng) => fixes.sublist(_firstAt(fixes, courseMi * fraction));

/// No fixes for [seconds] starting at [fraction] of the course: phone asleep,
/// tunnel, app backgrounded.
FixTransform gap(double fraction, double seconds) => (fixes, courseMi, rng) {
      int i = _firstAt(fixes, courseMi * fraction);
      if (i >= fixes.length) return fixes;
      double t0 = fixes[i].epoch;
      return [for (Fix f in fixes) if (f.epoch < t0 || f.epoch >= t0 + seconds) f];
    };

/// Shift fixes [meters] east for [seconds] starting at [fraction] of the
/// course: a detour off the course (bathroom, wrong turn) and back.
FixTransform excursion(double fraction, double seconds, double meters) => (fixes, courseMi, rng) {
      int i = _firstAt(fixes, courseMi * fraction);
      if (i >= fixes.length) return fixes;
      double t0 = fixes[i].epoch;
      return [
        for (Fix f in fixes)
          (f.epoch >= t0 && f.epoch < t0 + seconds)
              ? f.copyWith(lon: f.lon + meters / (111320.0 * math.cos(f.lat * math.pi / 180)))
              : f
      ];
    };

/// Add gaussian noise of [sigmaMeters] to every fix (accuracy left as is).
FixTransform noise(double sigmaMeters) => (fixes, courseMi, rng) {
      double g() => math.sqrt(-2 * math.log(1 - rng.nextDouble())) * math.cos(2 * math.pi * rng.nextDouble());
      return [
        for (Fix f in fixes)
          f.copyWith(
              lat: f.lat + g() * sigmaMeters / 111320.0,
              lon: f.lon + g() * sigmaMeters / (111320.0 * math.cos(f.lat * math.pi / 180)))
      ];
    };

/// Keep at most one fix per [seconds]: a phone in power-saving mode.
FixTransform sparse(double seconds) => (fixes, courseMi, rng) {
      List<Fix> out = [];
      for (Fix f in fixes) {
        if (out.isEmpty || f.epoch - out.last.epoch >= seconds) out.add(f);
      }
      return out;
    };

/// Before the first fix, [seconds] of milling about within roughly [radiusM]
/// of where the run starts: warming up or waiting in the corral. On a course
/// whose start is near its finish, this is what can complete a course before
/// the gun.
FixTransform warmUp(double seconds, double radiusM) => (fixes, courseMi, rng) {
      if (fixes.isEmpty) return fixes;
      Fix f = fixes.first;
      List<Fix> pre = wanderAround(f.lat, f.lon,
          start: f.epoch - seconds, seconds: seconds, radiusM: radiusM, rng: rng);
      return [
        for (Fix w in pre) Fix(w.epoch, w.lat, w.lon, w.accuracy, truth: f.truth, offM: double.nan),
        ...fixes
      ];
    };

// ------------------------------------------------------------------ the set

final Condition asIs = Condition("asIs", "the recording as is");
final Condition noSegments = Condition("noSegments", "segment markers removed", course: [stripSegments]);
final Condition lateStart25 = Condition("lateStart25", "app opened at 25% of the course", fixes: [lateStart(0.25)]);
final Condition lateStart60 = Condition("lateStart60", "app opened at 60% of the course", fixes: [lateStart(0.60)]);
final Condition gap5min = Condition("gap5min", "no fixes for 5 minutes at 50%", fixes: [gap(0.5, 300)]);
final Condition gap20min = Condition("gap20min", "no fixes for 20 minutes at 40%", fixes: [gap(0.4, 1200)]);
final Condition detour = Condition("detour", "200 m off course for 3 minutes at 40%", fixes: [excursion(0.4, 180, 200)]);
final Condition noisy = Condition("noisy", "20 m gaussian noise on every fix", fixes: [noise(20)]);
final Condition sparse15 = Condition("sparse15", "one fix per 15 s", fixes: [sparse(15)]);
final Condition warmUp10 = Condition("warmUp10", "10 minutes milling about within ~80 m of the start",
    fixes: [warmUp(600, 80)]);
final Condition restart = Condition("restart", "app restarted at 60%, history replayed",
    actions: [Action("restart", 0.6)]);
final Condition setDistance = Condition("setDistance", "remote set_distance to the true distance at 50%",
    actions: [Action("set_distance", 0.5)]);

/// Every condition, and every condition again without segment markers --
/// the case automatic segmentation would have to handle.
List<Condition> allConditions() {
  List<Condition> base = [
    asIs, warmUp10, lateStart25, lateStart60, gap5min, gap20min, detour, noisy, sparse15, restart, setDistance
  ];
  return [...base, for (Condition c in base) c == asIs ? noSegments : noSegments + c];
}

/// The default set: one of each kind of trouble, a few of them without
/// segment markers. REPLAY_CONDITIONS=all runs allConditions().
List<String> quickConditionNames = [
  "asIs", "warmUp10", "lateStart25", "gap20min", "detour", "noisy", "sparse15", "restart", "setDistance",
  "noSegments", "noSegments+lateStart25", "noSegments+sparse15",
];
