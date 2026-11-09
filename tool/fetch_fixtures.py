#!/usr/bin/env python3
"""Fetch real course and GPS data for the tracker's replay tests.

Two modes:

    tool/fetch_fixtures.py --courses [--force]
        Freeze every course path that has segment markers, from the production
        database (read-only, via tool/export_courses.py in the brooksee3port
        venv), into test/fixtures/courses/<race_id>_<race_event_id>.json.gz.
        These are committed: the tests run synthetic runners on them, so they
        never depend on the database again.

    tool/fetch_fixtures.py [--per-event 3] [--all-courses] [--force] [--out DIR] RACE_ID ...
        Sample real runners' tracks at those races. Fixes come from Firestore
        store-9dec1 /timing/tracking/points (publicly readable -- the collection
        the app writes). Each fixture is a race event's course plus a few
        tracks, every fix with the distance production reported and an offline
        reference position. Written to build/replay_fixtures/ (not committed):
        use it with test/replay/calibrate_test.dart to check the synthetic
        runner against real ones, and copy individual tracks into the committed
        set with tool/pick_tracks.py.

Existing files are never overwritten without --force: they are frozen
snapshots, and test/replay/baseline.json is tied to them. Needs numpy (system
python3).

The reference ("truth") position comes from aligning the whole track to the
course at once -- a monotone dynamic-programming alignment that can see the
future, so it is not fooled by a course that comes back near itself the way a
fix-by-fix matcher can be. It is an estimate, not ground truth, but a much
better one than any online matcher's. Participant and device ids are dropped.
"""
import argparse
import gzip
import json
import math
import os
import random
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TRACKS_DIR = os.path.join(HERE, "..", "build", "replay_fixtures")
COURSES_DIR = os.path.join(HERE, "..", "test", "fixtures", "courses")
BROOKSEE = os.environ.get("BROOKSEE3PORT", os.path.join(HERE, "..", "..", "..", "brooksee3port"))
FIRESTORE = ("https://firestore.googleapis.com/v1/projects/store-9dec1/databases/(default)"
             "/documents/timing/tracking:runQuery")

EARTH_RADIUS_METERS = 6371000
METERS_PER_MILE = 1609.344
MIN_DX_METERS = 10  # Tracker's interpolation spacing
MAX_ACCURACY = 50   # Tracker ignores fixes noisier than this
ORACLE_CAP_METERS = 150
ORACLE_MAX_CELLS = 40_000_000


# ---------------------------------------------------------------- Firestore

def run_query(query):
    body = json.dumps({"structuredQuery": query}).encode()
    req = urllib.request.Request(FIRESTORE, data=body, headers={"Content-Type": "application/json"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return [d["document"] for d in json.load(r) if "document" in d]
        except Exception as e:  # noqa: BLE001 -- retry transient network errors
            if attempt == 4:
                raise
            print(f"  retry after {e}", file=sys.stderr)


def num(v):
    for k in ("doubleValue", "integerValue"):
        if k in v:
            return float(v[k])
    raise ValueError(v)


def eq(field, value):
    return {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL",
                            "value": {"integerValue": str(value)}}}


def sample_pids(race_id, limit=4000):
    """Participants with fixes at this race. Document ids are random, so the
    first `limit` documents by name are a random sample of fixes."""
    docs = run_query({"from": [{"collectionId": "points"}], "where": eq("eid", race_id),
                      "select": {"fields": [{"fieldPath": "pid"}]}, "limit": limit})
    pids = {}
    for d in docs:
        pid = int(num(d["fields"]["pid"]))
        pids[pid] = pids.get(pid, 0) + 1
    return pids


def fetch_track(pid, page=5000):
    fields = ["epoch", "latM", "lngM", "accuracyK", "distK", "dev_id"]
    rows, cursor = [], None
    while True:
        q = {"from": [{"collectionId": "points"}], "where": eq("pid", pid),
             "select": {"fields": [{"fieldPath": f} for f in fields]},
             "orderBy": [{"field": {"fieldPath": "__name__"}, "direction": "ASCENDING"}],
             "limit": page}
        if cursor:
            q["startAt"] = {"values": [{"referenceValue": cursor}], "before": False}
        docs = run_query(q)
        for d in docs:
            f = d["fields"]
            rows.append((num(f["epoch"]), num(f["latM"]) / 1e6, num(f["lngM"]) / 1e6,
                         num(f["accuracyK"]) / 1000.0, num(f["distK"]) / 1000.0,
                         f.get("dev_id", {}).get("stringValue", "")))
        if len(docs) < page:
            break
        cursor = docs[-1]["name"]
    rows.sort()
    # one device per track: a participant who switched phones has two
    # interleaved streams; keep the device with the most fixes.
    devs = {}
    for r in rows:
        devs[r[5]] = devs.get(r[5], 0) + 1
    dev = max(devs, key=devs.get) if devs else ""
    out, last = [], None
    for r in rows:
        if r[5] != dev or (last is not None and r[0] == last):
            continue
        last = r[0]
        out.append([round(r[0], 3), round(r[1], 7), round(r[2], 7), round(r[3], 1), round(r[4], 3)])
    return out, len(devs)


# ------------------------------------------------- course, as Tracker builds it

def meters(lat1, lon1, lat2, lon2):
    lat1, lon1, lat2, lon2 = (math.radians(x) for x in (lat1, lon1, lat2, lon2))
    c = math.sin(lat1) * math.sin(lat2) + math.cos(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    return math.acos(max(-1.0, min(1.0, c))) * EARTH_RADIUS_METERS


def tracker_course(path):
    """The interpolated course points and their distances (miles), exactly as
    the Tracker constructor builds them."""
    pts = []
    for cp in path["points"]:
        for d in cp.get("directions") or []:
            pts.append((float(d["lat"]), float(d["lon"])))
        pts.append((float(cp["lat"]), float(cp["lon"])))
    out = []
    for i in range(len(pts) - 1):
        (a0, o0), (a1, o1) = pts[i], pts[i + 1]
        out.append(pts[i])
        n = int(math.floor(meters(a0, o0, a1, o1) / MIN_DX_METERS))
        for k in range(n):
            f = (k + 1) / (n + 1)
            out.append((a0 + (a1 - a0) * f, o0 + (o1 - o0) * f))
    if pts:
        out.append(pts[-1])
    dist = [0.0]
    for i in range(1, len(out)):
        dist.append(dist[-1] + meters(*out[i - 1], *out[i]) / METERS_PER_MILE)
    return np.array(out), np.array(dist)


def meters_to_all(lat, lon, course):
    lat1, lon1 = math.radians(lat), math.radians(lon)
    lat2, lon2 = np.radians(course[:, 0]), np.radians(course[:, 1])
    c = math.sin(lat1) * np.sin(lat2) + math.cos(lat1) * np.cos(lat2) * np.cos(lon2 - lon1)
    return np.arccos(np.clip(c, -1.0, 1.0)) * EARTH_RADIUS_METERS


# ------------------------------------------------------------------- oracle

def oracle(fixes, course, dist):
    """Reference course distance (miles) and distance off course (meters) for
    every fix: the monotone alignment of the whole track to the course that
    minimises total (capped) distance from fix to aligned course point."""
    good = [i for i, f in enumerate(fixes) if f[3] <= MAX_ACCURACY]
    if not good:
        return None
    span = fixes[good[-1]][0] - fixes[good[0]][0]
    step = max(5.0, span * len(course) / ORACLE_MAX_CELLS)
    rows, last = [], -1e18
    for i in good:
        if fixes[i][0] - last >= step:
            rows.append(i)
            last = fixes[i][0]
    n, c = len(rows), len(course)
    idx = np.arange(c)
    back = np.empty((n, c), dtype=np.int32)
    cost = np.minimum(meters_to_all(fixes[rows[0]][1], fixes[rows[0]][2], course), ORACLE_CAP_METERS)
    back[0] = idx
    for r in range(1, n):
        prev_min = np.minimum.accumulate(cost)
        before = np.concatenate(([np.inf], prev_min[:-1]))
        back[r] = np.maximum.accumulate(np.where(cost < before, idx, 0))
        d = meters_to_all(fixes[rows[r]][1], fixes[rows[r]][2], course)
        cost = prev_min + np.minimum(d, ORACLE_CAP_METERS)
    j = int(np.argmin(cost))
    aligned = [0] * n
    for r in range(n - 1, -1, -1):
        aligned[r] = j
        j = int(back[r][j])
    t_rows = np.array([fixes[i][0] for i in rows])
    d_rows = dist[aligned]
    times = np.array([f[0] for f in fixes])
    truth = np.interp(times, t_rows, d_rows)
    off = [float(np.min(meters_to_all(f[1], f[2], course[max(0, a - 50):a + 50])))
           for f, a in zip(fixes, np.interp(times, t_rows, aligned).astype(int))]
    return [round(float(t), 4) for t in truth], [round(o, 1) for o in off]


# ------------------------------------------------------------------- main

def export_courses(pids_by_race, segmented_only):
    return _export({"pids": {str(k): list(v) for k, v in pids_by_race.items()},
                    "segmented_only": segmented_only})


def _export(request):
    py = os.path.join(BROOKSEE, "env", "bin", "python")
    req = json.dumps(request)
    out = subprocess.run([py, "-I", os.path.join(HERE, "export_courses.py")], input=req,
                         capture_output=True, text=True, cwd=BROOKSEE, check=True)
    return json.loads(out.stdout)


def production_summary(fixes):
    # accuracy 0 marks a tag read the app turned into a fix; it arrives late,
    # so its distK is not where the tracker was at its epoch
    real = [f for f in fixes if f[3] > 0]
    jumps = [b[4] - a[4] for a, b in zip(real, real[1:])]
    return dict(max_jump_mi=round(max(jumps, default=0), 3), min_jump_mi=round(min(jumps, default=0), 3),
                final_mi=fixes[-1][4] if fixes else 0)


def course_fixture(ev, course_mi, tracks):
    return dict(race_id=ev["race_id"], race_event_id=ev["race_event_id"], path_id=ev["path_id"],
                race_date=ev["race_date"], segment_point_indexes=ev["segment_point_indexes"],
                course_mi=round(course_mi, 3), path=ev["path"],
                fix_fields=["epoch", "lat", "lon", "accuracy_m", "production_mi"], tracks=tracks)


def write_gz(fn, obj):
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    with gzip.open(fn, "wt") as f:
        json.dump(obj, f, separators=(",", ":"))


def fetch_courses(force):
    events = _export({"segmented_courses": True})
    kept = 0
    for ev in sorted(events, key=lambda e: (e["race_id"], e["race_event_id"])):
        fn = os.path.join(COURSES_DIR, f"{ev['race_id']}_{ev['race_event_id']}.json.gz")
        if os.path.exists(fn) and not force:
            continue
        _, dist = tracker_course(ev["path"])
        if len(dist) < 2:
            continue
        write_gz(fn, course_fixture(ev, float(dist[-1]), []))
        kept += 1
    print(f"{len(events)} segmented courses, {kept} written to {COURSES_DIR}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("race_ids", type=int, nargs="*")
    ap.add_argument("--courses", action="store_true", help="freeze every segmented course into the repo")
    ap.add_argument("--out", default=TRACKS_DIR, help="where sampled tracks go")
    ap.add_argument("--per-event", type=int, default=3)
    ap.add_argument("--candidates", type=int, default=8,
                    help="tracks fetched per race event to choose --per-event from")
    ap.add_argument("--all-courses", action="store_true", help="include courses without segment markers")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--force", action="store_true",
                    help="rebuild fixtures that already exist (the baseline is tied to the current ones)")
    args = ap.parse_args()
    if args.courses:
        fetch_courses(args.force)
        return
    if not args.race_ids:
        ap.error("give race ids, or --courses")
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(args.seed)

    with ThreadPoolExecutor(8) as ex:
        sampled = dict(zip(args.race_ids, ex.map(sample_pids, args.race_ids)))
    for rid, pids in sampled.items():
        print(f"race {rid}: {len(pids)} participants in sample", file=sys.stderr)
    events = export_courses({rid: list(p) for rid, p in sampled.items()}, not args.all_courses)
    print(f"{len(events)} race events to fetch", file=sys.stderr)

    for ev in events:
        name = f"{ev['race_id']}_{ev['race_event_id']}"
        if os.path.exists(os.path.join(args.out, name + ".json.gz")) and not args.force:
            print(f"{name}: exists, kept (--force to rebuild)", file=sys.stderr)
            continue
        # prefer runners with many fixes in the sample (long tracks), then random
        pids = sorted(ev["pids"], key=lambda p: -sampled[ev["race_id"]][p])
        pool = pids[: args.candidates * 2]
        rng.shuffle(pool)
        pool = pool[: args.candidates]
        with ThreadPoolExecutor(8) as ex:
            tracks = list(ex.map(fetch_track, pool))
        course, dist = tracker_course(ev["path"])
        cands = []
        for pid, (fixes, ndev) in zip(pool, tracks):
            if len(fixes) < 100:
                continue
            o = oracle(fixes, course, dist)
            if o is None:
                continue
            truth, off = o
            cands.append(dict(pid=pid, devices=ndev, fixes=fixes, truth=truth, off_m=off,
                              production=production_summary(fixes),
                              truth_final_mi=truth[-1], course_mi=round(float(dist[-1]), 3)))
        # keep variety: the most-anomalous production run, the longest run, then random
        keep = []
        if cands:
            keep.append(max(cands, key=lambda c: c["production"]["max_jump_mi"] - c["production"]["min_jump_mi"]))
            rest = [c for c in cands if c is not keep[0]]
            if rest:
                keep.append(max(rest, key=lambda c: c["truth_final_mi"]))
            rest = [c for c in cands if all(c is not k for k in keep)]
            rng.shuffle(rest)
            keep += rest[: max(0, args.per_event - len(keep))]
        for i, k in enumerate(keep):
            k["id"] = f"t{i}"
            del k["pid"]  # fixtures carry no participant or device ids
        fixture = course_fixture(ev, float(dist[-1]), keep)
        write_gz(os.path.join(args.out, name + ".json.gz"), fixture)
        print(f"{name}: course {fixture['course_mi']} mi, {len(ev['segment_point_indexes'])} markers, "
              f"{len(keep)} tracks "
              + " ".join(f"[{len(k['fixes'])} fixes, truth {k['truth_final_mi']} mi, prod jump "
                         f"{k['production']['max_jump_mi']}/{k['production']['min_jump_mi']}]" for k in keep),
              file=sys.stderr)


if __name__ == "__main__":
    main()
