import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/tracker.dart';

void main() {
  test('parses an Android fix whose accuracy is a whole number', () {
    // Android's JSONObject writes an accuracy of 4.0 as 4, so it decodes as an int.
    final j = jsonDecode('{"lat":34.2143744,"lon":-119.0054551,"ele":11,"acc":4,"epoch":1794166660050}');
    final loc = Location.fromJson(j);
    expect(loc.accuracy, 4.0);
    expect(loc.latLng.latitude, 34.2143744);
    expect(loc.latLng.longitude, -119.0054551);
    expect(loc.epoch, 1794166660.05);
  });

  test('parses an Android fix with fractional values', () {
    final j = jsonDecode('{"lat":34.2143744,"lon":-119.0054551,"ele":11.2,"acc":3.513,"epoch":1794166660050}');
    expect(Location.fromJson(j).accuracy, 3.513);
  });

  test('parses an iOS fix sent as a map of doubles', () {
    final loc = Location.fromJson({"lat": 34.2, "lon": -119.0, "acc": 5.0, "ele": 0.0, "epoch": 1794166660050.0});
    expect(loc.accuracy, 5.0);
    expect(loc.epoch, 1794166660.05);
  });
}
