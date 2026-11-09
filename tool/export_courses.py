"""Read-only export from the production database, run by fetch_fixtures.py
with the brooksee3port venv and the brooksee3port directory as cwd.

Reads JSON from stdin, one of:
  {"pids": {"<race_id>": [pid, ...]}, "segmented_only": bool}
      the race events those participants ran, with which pids ran each
  {"segmented_courses": true}
      every course path that has segment markers, once each, with the most
      recent race event that uses it
Writes JSON to stdout: a list of race events, each with its course path (as
the map editor stores it, Path.to_dict()).
"""
import json
import os
import sys

sys.path.insert(0, os.getcwd())
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "brooksee3port.settings")
import django  # noqa: E402

django.setup()
from event.models import Participant  # noqa: E402


def segment_indexes(points):
    out = []
    for i, p in enumerate(points):
        desc = (p.get("desc") or "").strip()
        if not desc:
            continue
        try:
            data = json.loads(desc)
        except ValueError:
            continue
        if isinstance(data, dict) and "segment" in data:
            out.append(i)
    return out


def event_row(re_, path, segs, pids=()):
    return dict(
        race_id=re_.race_id,
        race_name=re_.race.name,
        race_date=str(re_.race.date),
        race_event_id=re_.id,
        race_event_name=re_.name,
        path_id=re_.path_id,
        segment_point_indexes=segs,
        path=path,
        pids=sorted(pids),
    )


def segmented_courses():
    from gmaps.models import Path
    from event.models import RaceEvent
    out = []
    for p in Path.objects.filter(state__contains="segment"):
        path = p.to_dict()
        segs = segment_indexes(path["points"])
        if not segs:
            continue
        re_ = (RaceEvent.objects.filter(path=p).select_related("race")
               .order_by("-race__date", "-id").first())
        if re_ is not None:
            out.append(event_row(re_, path, segs))
    return out


def main():
    req = json.load(sys.stdin)
    if req.get("segmented_courses"):
        json.dump(segmented_courses(), sys.stdout)
        return
    segmented_only = req.get("segmented_only", True)
    events = {}
    for race_id, pids in req["pids"].items():
        rows = (Participant.objects.filter(id__in=pids, race_event__race_id=int(race_id))
                .values_list("id", "race_event_id"))
        for pid, re_id in rows:
            events.setdefault(re_id, []).append(pid)

    from event.models import RaceEvent
    out = []
    for re_ in RaceEvent.objects.filter(id__in=events).select_related("race", "path"):
        if re_.path is None:
            continue
        path = re_.path.to_dict()
        segs = segment_indexes(path["points"])
        if segmented_only and not segs:
            continue
        out.append(event_row(re_, path, segs, events[re_.id]))
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
