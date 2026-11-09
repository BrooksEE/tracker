// Pass/fail rules, the baseline comparison, and the markdown report.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'conditions.dart';
import 'harness.dart';

/// Rules any acceptable tracker must meet, whatever the condition.
List<String> invariantProblems(RunResult r, Condition c) => [
      if (r.earlyFinishM > 400)
        "declared the course complete ${r.earlyFinishM.round()} m before the runner reached the finish",
    ];

/// The measures compared against the baseline, and how much worse counts as
/// a regression.
const Map<String, num> regressionTolerance = {
  "ahead_max_m": 100,
  "behind_max_m": 200,
  "p95_abs_err_m": 50,
  "early_finish_m": 100,
  "stuck_min": 2,
  "big_jumps": 0,
};

class Baseline {
  final Map<String, Map> runs;
  Baseline(this.runs);

  static Baseline load(String path) {
    File f = File(path);
    if (!f.existsSync()) return Baseline({});
    Map j = jsonDecode(f.readAsStringSync());
    return Baseline({for (Map r in j["runs"]) "${r["fixture"]}/${r["track"]}/${r["condition"]}": r});
  }

  static void write(String path, List<RunResult> results) {
    List runs = [for (RunResult r in results) r.toJson()..remove("millis")]
      ..sort((a, b) => "${a["fixture"]}/${a["track"]}/${a["condition"]}"
          .compareTo("${b["fixture"]}/${b["track"]}/${b["condition"]}"));
    File(path).writeAsStringSync(const JsonEncoder.withIndent(" ").convert({"runs": runs}));
  }

  bool has(RunResult r) => runs.containsKey(r.key);

  /// Ways [r] is worse than the baseline run of the same fixture, track and
  /// condition. Empty when there is no baseline for it.
  List<String> regressions(RunResult r) {
    Map? b = runs[r.key];
    if (b == null) return [];
    Map now = r.toJson();
    return [
      for (MapEntry<String, num> e in regressionTolerance.entries)
        if ((now[e.key] as num) > (b[e.key] as num) + e.value) "${e.key}: ${b[e.key]} -> ${now[e.key]}",
      if (now["missed_finish"] == true && b["missed_finish"] != true) "missed_finish: now misses the finish",
    ];
  }

  /// Per measure: runs that got better, runs that got worse (beyond tolerance).
  Map<String, List<int>> compare(List<RunResult> results) {
    Map<String, List<int>> out = {for (String k in regressionTolerance.keys) k: [0, 0]};
    for (RunResult r in results) {
      Map? b = runs[r.key];
      if (b == null) continue;
      Map now = r.toJson();
      regressionTolerance.forEach((k, tol) {
        num d = (now[k] as num) - (b[k] as num);
        if (d < -tol) out[k]![0]++;
        if (d > tol) out[k]![1]++;
      });
    }
    return out;
  }
}

String markdownReport(List<RunResult> results, Map production, Baseline baseline) {
  StringBuffer s = StringBuffer();
  s.writeln("# Tracker replay report\n");
  s.writeln("${results.length} runs. Distances are meters along the course versus the reference position; "
      "`ahead` is how far the tracker got in front of the runner, `behind` how far it lagged.\n");

  s.writeln("## By condition\n");
  s.writeln("| condition | runs | ahead max (worst / median) | behind max (median) | p95 err (median) | "
      "early finish | missed finish | stuck > 5 min | big jumps | warnings | rematches |");
  s.writeln("|---|---|---|---|---|---|---|---|---|---|---|");
  Map<String, List<RunResult>> by = {};
  for (RunResult r in results) {
    by.putIfAbsent(r.condition, () => []).add(r);
  }
  double med(List<double> v) {
    v.sort();
    return v.isEmpty ? 0 : v[v.length ~/ 2];
  }

  by.forEach((c, rs) {
    s.writeln("| $c | ${rs.length} "
        "| ${rs.map((r) => r.aheadMaxM).reduce(math.max).round()} / ${med(rs.map((r) => r.aheadMaxM).toList()).round()} "
        "| ${med(rs.map((r) => r.behindMaxM).toList()).round()} "
        "| ${med(rs.map((r) => r.p95AbsErrM).toList()).round()} "
        "| ${rs.where((r) => r.earlyFinishM > 400).length} "
        "| ${rs.where((r) => r.missedFinish).length} "
        "| ${rs.where((r) => r.stuckMin > 5).length} "
        "| ${rs.fold<int>(0, (a, r) => a + r.bigJumps)} "
        "| ${rs.fold<int>(0, (a, r) => a + r.events.offCourseWarnings)} "
        "| ${rs.fold<int>(0, (a, r) => a + r.events.rematches)} |");
  });

  if (baseline.runs.isNotEmpty) {
    s.writeln("\n## Against the baseline\n");
    s.writeln("| measure | better | worse |");
    s.writeln("|---|---|---|");
    baseline.compare(results).forEach((k, v) => s.writeln("| $k | ${v[0]} | ${v[1]} |"));
  }

  s.writeln("\n## What production reported (distK), as is\n");
  s.writeln("| fixture/track | ahead max | behind max | p95 err |");
  s.writeln("|---|---|---|---|");
  production.forEach((k, v) =>
      s.writeln("| $k | ${v["ahead_max_m"]} | ${v["behind_max_m"]} | ${v["p95_abs_err_m"]} |"));

  s.writeln("\n## Every run\n");
  s.writeln("| run | segs | fixes | ahead | behind | p95 | finished | completed | early | stuck min | jumps | warn | rematch |");
  s.writeln("|---|---|---|---|---|---|---|---|---|---|---|---|---|");
  List<RunResult> sorted = [...results]..sort((a, b) => a.key.compareTo(b.key));
  for (RunResult r in sorted) {
    s.writeln("| ${r.key} | ${r.segments} | ${r.samples.length} | ${r.aheadMaxM.round()} | ${r.behindMaxM.round()} "
        "| ${r.p95AbsErrM.round()} | ${r.finished ? "y" : ""} | ${r.completed ? "y" : ""} | ${r.earlyFinishM.round()} "
        "| ${r.stuckMin.toStringAsFixed(1)} | ${r.bigJumps} | ${r.events.offCourseWarnings} | ${r.events.rematches} |");
  }
  return s.toString();
}
