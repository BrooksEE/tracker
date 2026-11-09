# Tracker replay tests

These tests run runners along real race courses through `Tracker`, under a
matrix of conditions, and measure how far the tracker's distance is from
where the runner really was. Use them to check that a change to the matcher
doesn't break anything, and to compare ideas against today's tracker.

    flutter test test/tracker_test.dart     # a few made-up courses: fast, no data
    flutter test test/replay_test.dart      # real courses

## Data (committed, frozen)

| path | what |
|---|---|
| `test/fixtures/courses/<race_id>_<race_event_id>.json.gz` | A real course path, exactly as the map editor stores it. Each course is frozen on the day it was fetched, so the tests never depend on the database. |
| `test/fixtures/real/<race_id>_<race_event_id>.json.gz` | A few real recorded tracks on those courses. They cover things a synthetic runner doesn't do (see below). Participant and device ids are removed. |

**Runners.** Each course gets a synthetic runner (`syntheticRunner` in
`synthetic.dart`), generated at test time from a fixed seed, so it never
changes:
- runs 3 m/s with a fix every 2 s
- 8 m of GPS error that drifts slowly, as real receivers' error does
- mills about the finish for 3 minutes afterwards

`REPLAY_SEEDS=1,2,3` adds more runners per course.

**Each fix carries its true course distance.** For a synthetic runner this
is exact. For a real track it is a reference position: the whole track
aligned to the course at once by a monotone dynamic-programming alignment.
That alignment sees the whole run, so a course that comes back near itself
can't fool it the way a fix-by-fix matcher can be fooled.

**Why synthetic runners are enough.** We sampled 96 real tracks on 32
segmented courses and compared them with synthetic runners on the same
courses (`calibrate_test.dart`):
- **Without segment markers:** they agreed on all 32 courses, at nearly the
  same magnitudes.
- **With markers:** they agreed on 27. The differences were:
  - one course where real runners warmed up near the start, now covered by
    the `warmUp10` condition
  - three individual runners, whose tracks are kept in `test/fixtures/real`
  - one course that is sensitive to GPS noise, where synthetic runners fail
    and real ones happened not to

## Getting more data

    tool/fetch_fixtures.py --courses                 # freeze every segmented course (needs DB access)
    tool/fetch_fixtures.py RACE_ID ...               # sample real tracks into build/replay_fixtures
    flutter test test/replay/calibrate_test.dart     # synthetic vs real on the sample -> build/replay/calibration.md
    tool/pick_tracks.py --courses                    # copy sampled courses into test/fixtures/courses
    tool/pick_tracks.py 168228_173913:t0             # keep a real track in test/fixtures/real

- **Courses** come from the production database (read-only), through
  `tool/export_courses.py` run in the `../../brooksee3port` venv (override
  with `BROOKSEE3PORT=`). The database only accepts allow-listed addresses.
- **Tracks** come from Firestore `store-9dec1` `/timing/tracking/points`,
  which is publicly readable.
- **Nothing is overwritten** without `--force`, because the baseline is tied
  to the frozen data.

A real track's fixes include tag reads that the app turns into fixes at the
reader's location, with `accuracy 0` and the read's time (race.dart,
syncScores). They reach the phone minutes late, so their recorded `distK` is
not where the tracker was at that time. The production comparison skips them.

## Running

| variable | meaning |
|---|---|
| `REPLAY_ONLY=168245` | only courses whose name contains this |
| `REPLAY_CONDITIONS=asIs,noSegments` / `all` | which conditions (default: `quickConditionNames`) |
| `REPLAY_SEEDS=1,2` | synthetic runners per course (default 1) |
| `REPLAY_JOBS=n` | parallel replays (default cores - 2) |
| `REPLAY_UPDATE_BASELINE=1` | write `test/replay/baseline.json` from this run (only a complete run) |

The test writes two reports:
- `build/replay/report.md`: a summary by condition, the comparison against
  the baseline, and every run.
- `build/replay/report.json`

## Conditions (`conditions.dart`)

| condition | what it does |
|---|---|
| `noSegments` | strips the segment markers, as if the timer forgot them |
| `warmUp10` | 10 minutes of milling about near the start before the gun |
| `lateStart25`, `lateStart60` | the app is opened mid-race |
| `gap5min`, `gap20min` | no fixes for a while |
| `detour` | 200 m off course for 3 minutes, then back |
| `noisy` | 20 m GPS noise |
| `sparse15` | one fix every 15 s |
| `restart` | the app relaunches and replays its history |
| `setDistance` | a remote `set_distance` command |

`noSegments + x` combines two conditions; `allConditions()` lists every
pairing.

## Pass / fail

- **Invariant** (`report.dart`): the tracker must never declare the course
  complete more than 400 m before the runner reaches the finish.
- **Baseline:** `baseline.json` records today's tracker on every run. Once a
  run is in the baseline, it fails only if a measure gets worse beyond
  `regressionTolerance`. Failures the baseline already has show in the
  report without failing the suite. After an intended improvement, run with
  `REPLAY_UPDATE_BASELINE=1` to make it the new bar.

## Measures

| measure | meaning |
|---|---|
| `ahead_max_m` | furthest the tracker got in front of the runner (what segments prevent) |
| `behind_max_m` | furthest it lagged |
| `p95_abs_err_m` | typical error |
| `early_finish_m` | how far short of the finish the runner was when the tracker declared completion |
| `missed_finish` | the runner finished but the tracker never completed |
| `stuck_min` | longest time more than 400 m behind |
| `big_jumps` | single-fix jumps over 300 m |

## Trying an idea

`replay()` takes a `factory` that builds the tracker under test. Pass it a
subclass of `Tracker`, or a `Tracker` with different thresholds, and compare
its report with the baseline's.
