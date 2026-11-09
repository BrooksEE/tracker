// Segment behaviour on made-up courses: runs without any fixtures.
// Real-data replays are in replay_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/tracker.dart';

import 'replay/conditions.dart';
import 'replay/harness.dart';
import 'replay/synthetic.dart';

Tracker _tracker(Map path) =>
    Tracker(pid: 0, eid: 0, uid: 0, eventType: EVENT_TYPE.RACE, appTitle: "t", deviceId: "t", coursePath: path);

void main() {
  group("segmentCourse", () {
    test("splits at the marker and repeats the boundary point", () {
      Tracker t = _tracker(outAndBack());
      expect(t.segments.length, 2);
      expect(t.segments[0]["latlngs"].last, t.segments[1]["latlngs"].first);
      expect(t.segments[1]["offset"], t.segments[0]["distances"].last);
    });

    test("no marker, one segment", () {
      expect(_tracker(outAndBack(marker: false)).segments.length, 1);
    });
  });

  group("set_distance", () {
    test("past the end of the course stops at the finish", () {
      // a re-match near the finish is rounded to 0.1 mi and can land past it
      Tracker t = _tracker(outAndBack());
      double total = t.distances!.last;
      t.set_distance(total + 0.05);
      expect(t.distance, closeTo(total, 1e-9));
    });

    test("mid-course resumes there", () {
      Tracker t = _tracker(outAndBack());
      t.set_distance(1.5);
      expect(t.distance, greaterThanOrEqualTo(1.5));
      expect(t.distance, lessThan(1.51));
      expect(t.segIdx, 1);
    });
  });

  // A runner on a two-way road with ordinary GPS noise (8 m).
  Condition gps = Condition("gps8", "8 m gaussian noise", fixes: [noise(8)]);

  group("out-and-back replay", () {
    test("with the turnaround marker the tracker follows the runner", () {
      var fx = syntheticFixture("out-and-back", outAndBack());
      RunResult r = replay(fx, fx.tracks.first, gps);
      expect(r.aheadMaxM, lessThan(60));
      expect(r.behindMaxM, lessThan(60));
      expect(r.completed, isTrue);
      expect(r.earlyFinishM, lessThan(50));
    });

    test("without the marker the tracker jumps to the return leg", () {
      // Documents today's behaviour -- the reason segments exist. An idea that
      // removes the need for the marker should flip this expectation.
      var fx = syntheticFixture("out-and-back", outAndBack(marker: false));
      RunResult r = replay(fx, fx.tracks.first, gps);
      expect(r.aheadMaxM, greaterThan(1000));
    });
  });
}
