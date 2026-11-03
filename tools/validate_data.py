#!/usr/bin/env python3
"""Checks the game's data files for the mistakes that only show up in play: a name that matches nothing, an event that
waits for an event that does not exist, a claim on a province that is not on the map.

    python3 tools/validate_data.py            # check data/ and say what is wrong
    python3 tools/validate_data.py --quiet    # print only the problems

Exits 0 when the data is sound and 1 when it is not. `check(root)` returns the list of problems (strings) for another
script or a test to use; `root` is a folder laid out like the project.
"""
import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))


def load_json(path: Path, problems: list):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        problems.append(f"{path.name}: the file is missing")
    except json.JSONDecodeError as e:
        problems.append(f"{path.name}: not valid JSON ({e})")
    return None


def read_tsv(path: Path, problems: list) -> list:
    try:
        with path.open(encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f, delimiter="\t"))
    except FileNotFoundError:
        problems.append(f"{path.name}: the file is missing")
        return []


def check(root: Path) -> list:
    problems: list = []
    data = root / "data"
    nations = load_json(data / "nations.json", problems) or {}
    tags = set(nations)
    provinces_rows = read_tsv(data / "map" / "provinces.tsv", problems)
    province_names = {r["name"] for r in provinces_rows}
    province_ids = {int(r["id"]) for r in provinces_rows}
    for r in provinces_rows:
        if r["owner"] and r["owner"] not in tags:
            problems.append(f"map/provinces.tsv: province {r['name']} is owned by unknown nation {r['owner']}")

    diplomacy = load_json(data / "diplomacy.json", problems) or {}
    cb_kinds = set(diplomacy.get("war", {}).get("casus_belli", {}))
    economy = load_json(data / "economy.json", problems) or {}
    building_ids = set(economy.get("buildings", {}))

    for name in ["clock", "military", "navy", "tutorial", "landmarks"]:
        load_json(data / f"{name}.json", problems)

    events = load_json(data / "events.json", problems) or {}
    check_events(events, tags, problems)
    check_focus(load_json(data / "focus.json", problems) or {}, tags, problems)
    check_crises(load_json(data / "crises.json", problems) or {}, problems)
    check_ai(root, problems)
    check_audio(root, load_json(data / "audio.json", problems) or {}, problems)

    scenarios = sorted(p for p in (data / "scenarios").iterdir() if p.is_dir()) if (data / "scenarios").exists() else []
    if not scenarios:
        problems.append("scenarios: none found")
    for folder in scenarios:
        check_scenario(folder, tags, province_names, province_ids, cb_kinds, building_ids, problems)
    return problems


def check_events(events: dict, tags: set, problems: list):
    items = events.get("events", [])
    ids = [e.get("id") for e in items]
    for i in set(ids):
        if ids.count(i) > 1:
            problems.append(f"events.json: the id {i} is used {ids.count(i)} times")
    known = set(ids)
    for e in items:
        eid = e.get("id", "?")
        for req in ([e["requires_event"]] if isinstance(e.get("requires_event"), str) else e.get("requires_event", []) or []):
            if req not in known:
                problems.append(f"events.json: {eid} waits for {req}, which is not an event")
        for key in ("date", "until"):
            d = e.get(key)
            if d is not None and not (isinstance(d, list) and len(d) in (2, 3) and all(isinstance(x, int) for x in d)):
                problems.append(f"events.json: {eid} has a bad {key} {d!r}")
        options = e.get("options", [])
        if not options:
            problems.append(f"events.json: {eid} has no options")
        for key in ("ai_option", "b_ai_option"):
            if key in e:
                pool = e.get("b_options", options) if key == "b_ai_option" else options
                choice = e[key]
                picks = [choice] if isinstance(choice, int) else [choice.get("yes"), choice.get("no")] if isinstance(choice, dict) else [None]
                if not all(isinstance(x, int) and 0 <= x < len(pool) for x in picks):
                    problems.append(f"events.json: {eid} {key} {choice!r} is not an option")
        # No decision has an option that does nothing (step 5 of PLAN.md).
        for i, o in enumerate(options + e.get("b_options", [])):
            if not any(any(v != 0 and v != [] and v != {} and not (isinstance(v, list) and len(v) > 1 and v[-1] == 0) for v in fx.values()) for fx in o.get("effects", [])):
                problems.append(f"events.json: {eid} option {i} ({o.get('label', '?')}) does nothing")
        for role, who in e.get("actors", {}).items():
            if isinstance(who, str) and not who.startswith("$") and who not in tags:
                problems.append(f"events.json: {eid} names unknown nation {who} as {role}")
            if isinstance(who, str) and who.startswith("$") and who not in PICKS:
                problems.append(f"events.json: {eid} picks {who} as {role}, which Pressure._pick_role does not know")
        for key in e.get("condition", {}):
            if key not in CONDITIONS:
                problems.append(f"events.json: {eid} has an unknown condition {key}")
    # Every nation has at least two events of its own to answer (step 5 of PLAN.md: no nation sits through the game unasked).
    named = {}
    for e in items:
        for who in set(v for v in e.get("actors", {}).values() if isinstance(v, str) and not v.startswith("$")):
            named[who] = named.get(who, 0) + 1
    for tag in sorted(tags):
        if named.get(tag, 0) < 2:
            problems.append(f"events.json: {tag} is in {named.get(tag, 0)} events (at least 2 wanted)")
    for tag in events.get("tension", {}).get("picks", {}).get("empires", []):
        if tag not in tags:
            problems.append(f"events.json: tension.picks.empires names unknown nation {tag}")


# What Pressure._pick_role and Pressure._condition_ok read.
PICKS = {"$player", "$lost_ground", "$winner", "$empire", "$most_armed", "$second_armed", "$suitor", "$trade_partner",
         "$great_neighbour"}
CONDITIONS = {"tension_min", "tension_max", "relation_above", "peace", "pressure_ai", "player_great_power", "player_minor",
              "no_great_war", "after_great_war", "months_from_start"}


def check_crises(crises: dict, problems: list):
    # Every kind of demand Crisis.demand_options makes needs its weight and its words.
    for kind in ("claim", "revanche", "border", "indemnity", "disarm", "naval"):
        k = crises.get("kinds", {}).get(kind)
        if not isinstance(k, dict):
            problems.append(f"crises.json: no kind {kind}")
            continue
        for key in ("weight", "title", "text"):
            if key not in k:
                problems.append(f"crises.json: kind {kind} has no {key}")
    naval = crises.get("kinds", {}).get("naval", {})
    for key in ("years", "min_ratio"):
        if key not in naval:
            problems.append(f"crises.json: kind naval has no {key}")


def check_focus(focus: dict, tags: set, problems: list):
    for tag, entry in focus.get("nations", {}).items():
        if tag not in tags:
            problems.append(f"focus.json: unknown nation {tag}")
        ids = {f.get("id") for f in entry.get("tree", [])}
        for f in entry.get("tree", []):
            for req in f.get("requires", []):
                if req not in ids:
                    problems.append(f"focus.json: {tag} focus {f.get('id')} requires {req}, which is not in its tree")


def check_ai(root: Path, problems: list):
    path = root / "data" / "ai.json"
    cfg = load_json(path, problems)
    if cfg is None:
        return
    try:
        import ai_train
    except Exception as e:  # the trainer is optional to a data check
        problems.append(f"ai.json: cannot read the trainer's parameter table ({e})")
        return
    for dotted, lo, hi, integer in ai_train.PARAMS:
        try:
            v = ai_train.lookup(cfg, dotted)
        except (KeyError, TypeError):
            problems.append(f"ai.json: the trained parameter {dotted} is missing")
            continue
        if not isinstance(v, (int, float)) or isinstance(v, bool):
            problems.append(f"ai.json: {dotted} is not a number")
        elif not lo - 1e-9 <= v <= hi + 1e-9:
            problems.append(f"ai.json: {dotted} = {v} is outside the trained range {lo} to {hi}")


def check_audio(root: Path, audio: dict, problems: list):
    music = audio.get("music", {})
    ids = {t["id"] for t in music.get("tracks", [])}
    for t in music.get("tracks", []):
        if not (root / "data" / "audio" / t["file"]).exists():
            problems.append(f"audio.json: the piece {t['id']} has no file {t['file']}")
    for key in ("menu", "peace", "war"):
        for i in music.get(key, []):
            if i not in ids:
                problems.append(f"audio.json: the {key} list names {i}, which is not a piece")
    for name, e in audio.get("events", {}).items():
        if isinstance(e, dict) and "file" in e and not (root / "data" / "audio" / e["file"]).exists():
            problems.append(f"audio.json: event {name} has no file {e['file']}")


def check_scenario(folder: Path, tags: set, province_names: set, province_ids: set, cb_kinds: set, building_ids: set, problems: list):
    label = folder.name
    sc = load_json(folder / "scenario.json", problems)
    if sc is None:
        return

    def nation(tag, where):
        if tag not in tags:
            problems.append(f"{label}: {where} names unknown nation {tag}")

    for tag in sc.get("nations", {}):
        nation(tag, "nations")
    for tag, spots in sc.get("deployment", {}).items():
        nation(tag, "deployment")
        for s in spots:
            if s.get("at") not in province_names:
                problems.append(f"{label}: deployment of {tag} is at {s.get('at')!r}, which is not a province")
    for bloc, members in sc.get("blocs", {}).items():
        for t in members:
            nation(t, f"bloc {bloc}")
    for g in sc.get("guarantees", []):
        nation(g["guarantor"], "guarantees")
        nation(g["guaranteed"], "guarantees")
    for key in ("alliances", "passage", "nap"):
        for t in sc.get(key, []):
            nation(t["a"], key)
            nation(t["b"], key)
    for r in sc.get("relations", []):
        nation(r["a"], "relations")
        nation(r["b"], "relations")
    for pair in sc.get("starting_wars", []):
        for t in pair:
            nation(t, "starting_wars")
    for c in sc.get("claims", []):
        nation(c["holder"], "claims")
        if cb_kinds and c["kind"] not in cb_kinds:
            problems.append(f"{label}: a claim of {c['holder']} has the unknown casus belli {c['kind']}")
        for p in c["provinces"]:
            if p not in province_names:
                problems.append(f"{label}: a claim of {c['holder']} names {p!r}, which is not a province")
    for p, owner in sc.get("owner_changes", {}).items():
        if p not in province_names:
            problems.append(f"{label}: owner_changes names {p!r}, which is not a province")
        nation(owner, "owner_changes")
    for city, b in sc.get("buildings", {}).items():
        for kind in b:
            if building_ids and kind not in building_ids:
                problems.append(f"{label}: {city} has the unknown building {kind}")

    for r in read_tsv(folder / "provinces.tsv", problems):
        if int(r["id"]) not in province_ids:
            problems.append(f"{label}/provinces.tsv: id {r['id']} is not a province")
    for r in read_tsv(folder / "cities.tsv", problems):
        if int(r["province"]) not in province_ids:
            problems.append(f"{label}/cities.tsv: {r['name']} is in province {r['province']}, which does not exist")
    for r in read_tsv(folder / "navy.tsv", problems):
        nation(r["tag"], "navy.tsv")


def main(argv: list) -> int:
    quiet = "--quiet" in argv
    problems = check(ROOT)
    for p in problems:
        print("PROBLEM:", p)
    if not problems and not quiet:
        print("the data is sound")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
