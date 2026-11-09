// Replay fixtures: a race event's course plus real runners' recorded fixes,
// built by tool/fetch_fixtures.py.
import 'dart:convert';
import 'dart:io';

class Fix {
  final double epoch;
  final double lat;
  final double lon;
  final double accuracy;

  /// The on-phone tracker's distance (miles) when this fix was recorded --
  /// what production actually did. NaN for synthetic fixes.
  final double production;

  /// Reference course distance (miles) from aligning the whole track offline.
  final double truth;

  /// Reference distance off course (meters).
  final double offM;

  const Fix(this.epoch, this.lat, this.lon, this.accuracy,
      {this.production = double.nan, this.truth = double.nan, this.offM = double.nan});

  Fix copyWith({double? epoch, double? lat, double? lon, double? accuracy}) => Fix(
      epoch ?? this.epoch, lat ?? this.lat, lon ?? this.lon, accuracy ?? this.accuracy,
      production: production, truth: truth, offM: offM);
}

class Track {
  final String id;
  final List<Fix> fixes;
  final double truthFinal;
  Track(this.id, this.fixes, this.truthFinal);
}

class Fixture {
  final String name;
  final int raceId;
  final int raceEventId;
  final double courseMi;
  final List<int> segmentPointIndexes;
  final Map path; // raw course path, as the app receives it
  final List<Track> tracks;
  Fixture(this.name, this.raceId, this.raceEventId, this.courseMi, this.segmentPointIndexes,
      this.path, this.tracks);

  /// A fresh, mutable copy of the course (Tracker modifies the one it's given).
  Map coursePath() => jsonDecode(jsonEncode(path)) as Map;

  static Fixture load(File f) {
    Map j = jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync())));
    List<Track> tracks = [];
    for (Map t in j["tracks"]) {
      List fixes = t["fixes"], truth = t["truth"], off = t["off_m"];
      tracks.add(Track(t["id"], [
        for (int i = 0; i < fixes.length; i++)
          Fix(_d(fixes[i][0]), _d(fixes[i][1]), _d(fixes[i][2]), _d(fixes[i][3]),
              production: _d(fixes[i][4]), truth: _d(truth[i]), offM: _d(off[i]))
      ], _d(t["truth_final_mi"])));
    }
    String name = f.uri.pathSegments.last.replaceAll(".json.gz", "");
    return Fixture(name, j["race_id"], j["race_event_id"], _d(j["course_mi"]),
        List<int>.from(j["segment_point_indexes"]), j["path"], tracks);
  }

  static List<Fixture> loadAll(String dir) {
    Directory d = Directory(dir);
    if (!d.existsSync()) return [];
    List<File> files = d.listSync().whereType<File>().where((f) => f.path.endsWith(".json.gz")).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files.map(load).toList();
  }
}

double _d(dynamic v) => (v as num).toDouble();
