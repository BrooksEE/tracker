import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/tracker.dart';

TrackerProgress p({
  double distance = 8.2,
  double? total = 26.2,
  String units = "mi",
  double? startEpoch = 1700000000,
  String? pace = "08:29",
  String? status,
}) =>
    TrackerProgress(
      distance: distance,
      total: total,
      units: units,
      startEpoch: startEpoch,
      pace: pace,
      status: status,
    );

void main() {
  group('TrackerProgress.text', () {
    test('running shows distance of total and pace', () {
      expect(p().text, "8.2 of 26.2 mi · 08:29/mi");
    });

    test('no pace yet', () {
      expect(p(pace: null).text, "8.2 of 26.2 mi");
    });

    test('total not known yet', () {
      expect(p(total: null, pace: null).text, "8.2 mi");
    });

    test('waiting for start shows only the status', () {
      expect(
          p(distance: 0, startEpoch: null, pace: null, status: "Waiting for start").text,
          "Waiting for start");
    });

    test('off course replaces pace with the status', () {
      expect(p(status: "Off course").text, "Off course · 8.2 of 26.2 mi");
    });

    test('metric', () {
      expect(p(distance: 5, total: 21.1, units: "km", pace: "05:10").text,
          "5.0 of 21.1 km · 05:10/km");
    });
  });

  group('TrackerProgress.chip', () {
    // Android shows the status-bar chip in full only under 7 characters.
    for (final d in [0.0, 8.24, 13.1, 26.2, 99.9, 99.96, 100.0, 162.4, 999.0]) {
      test('$d mi fits in 6 characters', () {
        expect(p(distance: d).chip!.length, lessThanOrEqualTo(6));
      });
    }

    test('no chip before the start', () {
      expect(p(distance: 0, startEpoch: null, pace: null, status: "Waiting for start").chip,
          isNull);
      expect(p(distance: 0, startEpoch: null, pace: null, status: "Waiting for start")
          .toMap()["chip"], isNull);
    });

    test('chip while off course', () {
      expect(p(status: "Off course").chip, "8.2mi");
    });

    test('one decimal under 100, whole number from 100', () {
      expect(p(distance: 13.14).chip, "13.1mi");
      expect(p(distance: 99.96).chip, "100mi");
      expect(p(distance: 100.4).chip, "100mi");
    });
  });

  test('toMap carries the derived text and chip', () {
    final m = p().toMap();
    expect(m["text"], "8.2 of 26.2 mi · 08:29/mi");
    expect(m["chip"], "8.2mi");
    expect(m["startEpoch"], 1700000000);
    expect(m["total"], 26.2);
  });
}
