// Does the synthetic runner behave like real runners? For every sampled
// course in build/replay_fixtures (tool/fetch_fixtures.py RACE_ID ...), this
// replays the real tracks and synthetic runners on the same course, with and
// without segment markers, and reports per course whether both went wrong.
// Skipped when there is no sample. Writes build/replay/calibration.md.
//
//   flutter test test/replay/calibrate_test.dart
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'conditions.dart';
import 'fixture.dart';
import 'harness.dart';
import 'synthetic.dart';

const String sampleDir = "build/replay_fixtures";

/// A run went wrong: well ahead of the runner, finished early, or missed the
/// finish.
bool wentWrong(Map r) => r["ahead_max_m"] > 500 || r["early_finish_m"] > 400 || r["missed_finish"] == true;

Future<Map> _replay(Fixture fx, Track? track, Condition c, int seed) => Isolate.run(() {
      Track t = track ?? syntheticRunner(fx.coursePath(), seed);
      return replay(fx, t, c).toJson();
    });

void main() {
  List<Fixture> fixtures = Fixture.loadAll(sampleDir);
  test("synthetic runners match real ones", () async {
    // every replay, run through a pool of isolates
    List<(Fixture, Track?, Condition, int)> jobs = [
      for (Condition c in [asIs, noSegments])
        for (Fixture fx in fixtures) ...[
          for (Track t in fx.tracks) (fx, t, c, 0),
          for (int seed in [1, 2, 3]) (fx, null, c, seed),
        ]
    ];
    List<Map?> out = List.filled(jobs.length, null);
    int next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        int i = next++;
        var (fx, t, c, seed) = jobs[i];
        out[i] = await _replay(fx, t, c, seed);
      }
    }

    await Future.wait([for (int i = 0; i < Platform.numberOfProcessors - 2; i++) worker()]);

    StringBuffer s = StringBuffer("# Synthetic vs real runners\n\n");
    for (Condition c in [asIs, noSegments]) {
      int agree = 0;
      s.writeln("## ${c.name}\n\n| course | real | synthetic | real ahead (m) | synthetic ahead (m) |\n|---|---|---|---|---|");
      for (Fixture fx in fixtures) {
        List<Map> real = [], syn = [];
        for (int i = 0; i < jobs.length; i++) {
          var (f, t, cc, _) = jobs[i];
          if (f == fx && cc == c) (t == null ? syn : real).add(out[i]!);
        }
        bool rb = real.any(wentWrong), sb = syn.any(wentWrong);
        if (rb == sb) agree++;
        s.writeln("| ${fx.name} | ${rb ? "wrong" : "ok"} | ${sb ? "wrong" : "ok"} "
            "| ${real.map((r) => r["ahead_max_m"]).join(", ")} | ${syn.map((r) => r["ahead_max_m"]).join(", ")} |");
      }
      s.writeln("\nAgree on $agree of ${fixtures.length} courses.\n");
    }
    Directory("build/replay").createSync(recursive: true);
    File("build/replay/calibration.md").writeAsStringSync(s.toString());
  }, skip: fixtures.isEmpty ? "no sample in $sampleDir -- run tool/fetch_fixtures.py RACE_ID ..." : false,
      timeout: Timeout.none);
}
