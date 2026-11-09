#!/usr/bin/env python3
"""Copy data from sampled fixtures (build/replay_fixtures, see
fetch_fixtures.py) into the committed test set.

    tool/pick_tracks.py --courses                       # every sampled course, no tracks
    tool/pick_tracks.py 168228_173913:t0 168229_174278:t0 ...

The first writes test/fixtures/courses/<name>.json.gz (course only) for every
sample that isn't there yet. The second writes the named real tracks to
test/fixtures/real/<name>.json.gz, merging with tracks already kept for that
course. Existing files are kept unless --force.
"""
import argparse
import glob
import gzip
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "build", "replay_fixtures")
COURSES = os.path.join(HERE, "..", "test", "fixtures", "courses")
REAL = os.path.join(HERE, "..", "test", "fixtures", "real")


def load(fn):
    with gzip.open(fn, "rt") as f:
        return json.load(f)


def save(fn, obj):
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    with gzip.open(fn, "wt") as f:
        json.dump(obj, f, separators=(",", ":"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tracks", nargs="*", help="FIXTURE:TRACK, e.g. 168228_173913:t0")
    ap.add_argument("--courses", action="store_true")
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if args.courses:
        n = 0
        for fn in sorted(glob.glob(os.path.join(args.src, "*.json.gz"))):
            out = os.path.join(COURSES, os.path.basename(fn))
            if os.path.exists(out) and not args.force:
                continue
            fx = load(fn)
            fx["tracks"] = []
            save(out, fx)
            n += 1
        print(f"{n} courses written to {COURSES}", file=sys.stderr)

    for spec in args.tracks:
        name, tid = spec.split(":")
        fx = load(os.path.join(args.src, name + ".json.gz"))
        track = next(t for t in fx["tracks"] if t["id"] == tid)
        out = os.path.join(REAL, name + ".json.gz")
        kept = load(out) if os.path.exists(out) else dict(fx, tracks=[])
        if any(t["id"] == tid for t in kept["tracks"]) and not args.force:
            print(f"{spec}: already kept", file=sys.stderr)
            continue
        kept["tracks"] = [t for t in kept["tracks"] if t["id"] != tid] + [track]
        save(out, kept)
        print(f"{spec}: {len(track['fixes'])} fixes -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
