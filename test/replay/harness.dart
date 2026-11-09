// Replays a fixture track through a Tracker and measures how its distance
// compares with the reference (truth) position.
import 'dart:async';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tracker/tracker.dart';

import 'conditions.dart';
import 'fixture.dart';

const double metersPerMile = Tracker.METERS_PER_MILE;

/// Callbacks a tracker under test reports to.
class TrackerEvents {
  int offCourseWarnings = 0;
  int rematches = 0;
  int backOnCourse = 0;
  int? completedAtFix;
  int currentFix = 0;
  final List<double> rematchDistances = [];
}

/// Builds the tracker under test. Swap this to try an idea: a subclass of
/// Tracker, or a Tracker with different thresholds.
typedef TrackerFactory = Tracker Function(Map coursePath, TrackerEvents events);

Tracker defaultTracker(Map coursePath, TrackerEvents ev) => Tracker(
      pid: 0,
      eid: 0,
      uid: 0,
      eventType: EVENT_TYPE.RACE,
      appTitle: "replay",
      deviceId: "replay",
      coursePath: coursePath,
      onOffCourse: () => ev.offCourseWarnings++,
      onMatchedNewLocation: (d) {
        ev.rematches++;
        ev.rematchDistances.add(d);
      },
      onBackOnCourse: (d) => ev.backOnCourse++,
      onPathCompleted: () => ev.completedAtFix ??= ev.currentFix,
    );

class Sample {
  final double epoch, truth, distance;
  final int segIdx;
  Sample(this.epoch, this.truth, this.distance, this.segIdx);
}

class RunResult {
  final String fixture, track, condition;
  final double courseMi;
  final double truthFinalMi;
  final List<Sample> samples;
  final TrackerEvents events;
  final int segments;
  final int millis;
  RunResult(this.fixture, this.track, this.condition, this.courseMi, this.truthFinalMi, this.samples,
      this.events, this.segments, this.millis);

  String get key => "$fixture/$track/$condition";

  Iterable<double> get _errM => samples.map((s) => (s.distance - s.truth) * metersPerMile);

  /// Furthest the tracker got ahead of the runner (m). Jumping ahead is what
  /// segments exist to prevent.
  double get aheadMaxM => _errM.fold(0.0, math.max);

  /// Furthest the tracker fell behind the runner (m).
  double get behindMaxM => -_errM.fold(0.0, math.min);

  double get p95AbsErrM {
    List<double> e = _errM.map((x) => x.abs()).toList()..sort();
    return e.isEmpty ? 0 : e[(0.95 * (e.length - 1)).round()];
  }

  /// Did the runner (per the reference) reach the end of the course?
  bool get finished => truthFinalMi >= courseMi - 0.1;

  bool get completed => events.completedAtFix != null;

  /// How far short of the finish the runner really was when the tracker
  /// declared the course complete (m). 0 if it completed on time or never.
  double get earlyFinishM {
    int? i = events.completedAtFix;
    if (i == null || i >= samples.length) return 0;
    return math.max(0, (courseMi - samples[i].truth) * metersPerMile);
  }

  bool get missedFinish => finished && !completed;

  /// Longest stretch (minutes) the tracker was more than 400 m behind.
  double get stuckMin {
    double best = 0;
    double? since;
    for (Sample s in samples) {
      bool behind = (s.truth - s.distance) * metersPerMile > 400;
      if (behind) {
        since ??= s.epoch;
        best = math.max(best, s.epoch - since);
      } else {
        since = null;
      }
    }
    return best / 60;
  }

  /// Single-fix forward jumps of more than 300 m along the course.
  int get bigJumps {
    int n = 0;
    for (int i = 1; i < samples.length; i++) {
      if ((samples[i].distance - samples[i - 1].distance) * metersPerMile > 300) n++;
    }
    return n;
  }

  Map<String, dynamic> toJson() => {
        "fixture": fixture,
        "track": track,
        "condition": condition,
        "course_mi": courseMi,
        "segments": segments,
        "fixes": samples.length,
        "ahead_max_m": aheadMaxM.round(),
        "behind_max_m": behindMaxM.round(),
        "p95_abs_err_m": p95AbsErrM.round(),
        "finished": finished,
        "completed": completed,
        "early_finish_m": earlyFinishM.round(),
        "missed_finish": missedFinish,
        "stuck_min": double.parse(stuckMin.toStringAsFixed(1)),
        "big_jumps": bigJumps,
        "off_course_warnings": events.offCourseWarnings,
        "rematches": events.rematches,
        "millis": millis,
      };
}

int _firstAt(List<Fix> fixes, double mi) {
  for (int i = 0; i < fixes.length; i++) {
    if (fixes[i].truth >= mi) return i;
  }
  return -1;
}

/// Replay [track] of [fx] under [condition]. Tracker output (print) is
/// silenced.
RunResult replay(Fixture fx, Track track, Condition condition,
    {TrackerFactory factory = defaultTracker, int seed = 1}) {
  math.Random rng = math.Random(seed);
  List<Fix> fixes = track.fixes;
  for (FixTransform t in condition.fixes) {
    fixes = t(fixes, fx.courseMi, rng);
  }
  Map<int, String> actionAt = {
    for (Action a in condition.actions) _firstAt(fixes, fx.courseMi * a.atFraction): a.kind
  }..remove(-1);

  Map course() {
    Map p = fx.coursePath();
    for (CourseTransform t in condition.course) {
      p = t(p);
    }
    return p;
  }

  TrackerEvents ev = TrackerEvents();
  List<Sample> samples = [];
  late Tracker tracker;
  Stopwatch sw = Stopwatch()..start();
  runZoned(() {
    tracker = factory(course(), ev);
    for (int i = 0; i < fixes.length; i++) {
      ev.currentFix = i;
      String? action = actionAt[i];
      if (action == "restart") {
        // the app relaunches: a new Tracker replays the fixes uploaded so far
        tracker = factory(course(), ev);
        for (int k = 0; k < i; k++) {
          Fix f = fixes[k];
          tracker.addPoint(Location(latLng: LatLng(f.lat, f.lon), epoch: f.epoch, accuracy: f.accuracy),
              replay: true);
        }
      } else if (action == "set_distance") {
        tracker.set_distance((fixes[i].truth * 10).round() / 10.0);
      }
      Fix f = fixes[i];
      tracker.addPoint(Location(latLng: LatLng(f.lat, f.lon), epoch: f.epoch, accuracy: f.accuracy));
      samples.add(Sample(f.epoch, f.truth, tracker.distance, tracker.segIdx));
    }
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {}));
  return RunResult(fx.name, track.id, condition.name, fx.courseMi, track.truthFinal, samples, ev,
      tracker.segments.length, sw.elapsedMilliseconds);
}

/// The same measures for what the phone actually reported in production
/// (the distK recorded with each fix), for comparison with the replay.
///
/// Fixes with accuracy 0 are skipped: those are tag reads the app turns into
/// a fix at the reader's location (race.dart, syncScores) with the read's
/// time as epoch. They reach the phone minutes after the runner passed the
/// reader, so their distK is the distance minutes later, not a jump.
Map<String, dynamic> productionSummary(Fixture fx, Track track) {
  List<double> err = [
    for (Fix f in track.fixes)
      if (!f.production.isNaN && f.accuracy > 0) (f.production - f.truth) * metersPerMile
  ];
  List<double> abs = err.map((e) => e.abs()).toList()..sort();
  return {
    "ahead_max_m": err.fold(0.0, math.max).round(),
    "behind_max_m": (-err.fold(0.0, math.min)).round(),
    "p95_abs_err_m": abs.isEmpty ? 0 : abs[(0.95 * (abs.length - 1)).round()].round(),
  };
}
