// Replays runs on real race courses through the tracker under a matrix of
// conditions and compares the tracker's distance with where the runner was.
//
// The runs are synthetic runners on every frozen course in
// test/fixtures/courses (made at test time from a fixed seed), plus the few
// real recorded tracks in test/fixtures/real. See test/replay/README.md.
//
//   flutter test test/replay_test.dart
//
// Environment:
//   REPLAY_ONLY=substr        only courses whose name contains substr
//   REPLAY_CONDITIONS=a,b|all these conditions (default: quickConditionNames)
//   REPLAY_SEEDS=1,2          synthetic runners per course (default: 1)
//   REPLAY_UPDATE_BASELINE=1  write test/replay/baseline.json from this run
//   REPLAY_JOBS=n             parallel replays (default: cores - 2)
//
// Writes build/replay/report.json and build/replay/report.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'replay/conditions.dart';
import 'replay/fixture.dart';
import 'replay/harness.dart';
import 'replay/report.dart';
import 'replay/synthetic.dart';

/// Every frozen course with its runners: synthetic ones for [seeds], then
/// the real tracks kept for that course, if any.
List<Fixture> loadFixtures(List<int> seeds, String only) {
  Map<String, Fixture> real = {for (Fixture f in Fixture.loadAll("test/fixtures/real")) f.name: f};
  return [
    for (Fixture c in Fixture.loadAll("test/fixtures/courses"))
      if (c.name.contains(only))
        Fixture(c.name, c.raceId, c.raceEventId, c.courseMi, c.segmentPointIndexes, c.path, [
          for (int seed in seeds) syntheticRunner(c.coursePath(), seed),
          ...?real[c.name]?.tracks,
        ])
  ];
}

void main() {
  Map<String, String> env = Platform.environment;
  List<int> seeds = (env["REPLAY_SEEDS"] ?? "1").split(",").map(int.parse).toList();
  List<Fixture> fixtures = loadFixtures(seeds, env["REPLAY_ONLY"] ?? "");
  List<Condition> conditions = allConditions();
  String want = env["REPLAY_CONDITIONS"] ?? quickConditionNames.join(",");
  if (want != "all") {
    Set<String> names = want.split(",").toSet();
    conditions = conditions.where((c) => names.contains(c.name)).toList();
  }
  Baseline baseline = Baseline.load("test/replay/baseline.json");
  List<RunResult> results = [];

  if (fixtures.isEmpty) {
    test("replay fixtures", () {}, skip: "no courses in test/fixtures/courses");
    return;
  }

  // Replays run in a pool of isolates, started by the first test, in the
  // same order as the tests; each test waits for its own result.
  List<(Fixture, Track, Condition)> jobs = [
    for (Fixture fx in fixtures)
      for (Track t in fx.tracks)
        for (Condition c in conditions) (fx, t, c)
  ];
  String keyOf(Fixture fx, Track t, Condition c) => "${fx.name}/${t.id}/${c.name}";
  // completes with a RunResult, or the error the replay threw
  Map<String, Completer<Object>> pending = {for (var (fx, t, c) in jobs) keyOf(fx, t, c): Completer()};
  bool started = false;
  void startPool() {
    if (started) return;
    started = true;
    int workers = int.tryParse(env["REPLAY_JOBS"] ?? "") ?? math.max(1, Platform.numberOfProcessors - 2);
    int next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        var (fx, t, c) = jobs[next++];
        Completer<Object> done = pending[keyOf(fx, t, c)]!;
        try {
          done.complete(await _replayInIsolate(fx, t, c));
        } catch (e, st) {
          done.complete("$e\n$st");
        }
      }
    }

    for (int i = 0; i < workers; i++) {
      worker();
    }
  }

  for (Fixture fx in fixtures) {
    group(fx.name, () {
      for (Track track in fx.tracks) {
        for (Condition c in conditions) {
          test("${track.id} ${c.name}", () async {
            startPool();
            Object r = await pending[keyOf(fx, track, c)]!.future;
            if (r is! RunResult) fail("replay threw: $r");
            results.add(r);
            // once a run is in the baseline, the baseline governs it: only a
            // regression fails (known failures stay visible in the report)
            List<String> broken = baseline.has(r) ? [] : invariantProblems(r, c);
            for (String problem in [...broken, ...baseline.regressions(r)]) {
              fail(problem);
            }
          }, timeout: Timeout.none);
        }
      }
    });
  }

  tearDownAll(() {
    Directory("build/replay").createSync(recursive: true);
    Map prod = {
      for (Fixture fx in fixtures)
        for (Track t in fx.tracks)
          if (t.fixes.any((f) => !f.production.isNaN)) "${fx.name}/${t.id}": productionSummary(fx, t)
    };
    File("build/replay/report.json").writeAsStringSync(const JsonEncoder.withIndent(" ").convert({
      "runs": [for (RunResult r in results) r.toJson()],
      "production": prod,
    }));
    File("build/replay/report.md").writeAsStringSync(markdownReport(results, prod, baseline));
    // only a complete run may become the baseline
    if (env["REPLAY_UPDATE_BASELINE"] == "1" && results.length == jobs.length) {
      Baseline.write("test/replay/baseline.json", results);
    }
  });
}

// Top level so the isolate's closure captures only its arguments.
Future<RunResult> _replayInIsolate(Fixture fx, Track t, Condition c) => Isolate.run(() => replay(fx, t, c));
