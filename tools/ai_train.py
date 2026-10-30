#!/usr/bin/env python3
"""Trains the AI's fighting and peace-making by self-play (an evolution strategy), with no historical target.

    python3 tools/ai_train.py run [generations]   # continue (or start) training; state in tools/ai_training/
    python3 tools/ai_train.py test [games]        # arena: the trained parameters against the ones in git HEAD
    python3 tools/ai_train.py apply               # write the trained numbers into data/ai.json

How it works. The parameters are numbers in data/ai.json (the PARAMS table: path, lowest, highest). A generation
samples candidates around the champion in mirrored pairs; each plays the champion for a handful of seeds in
tools/ai_arena.gd, with half of Europe's nations under one set of numbers and half under the other, and then again with
the halves swapped. A nation's score is what it gained in Europe's people, output and provinces (and a little for its
share of soldiers), less a little for each month at war (tools/ai_arena.gd); the candidate's fitness is how much
better its nations did than the same nations under the champion. Nothing names a nation or a battle. The champion moves toward the candidates that did better (rank-weighted), and the step shrinks as
it goes. Only the way the AI fights and makes peace is trained: the numbers that decide whether a nation goes to war
at all are left alone, so training cannot make the AI warlike.
"""
import concurrent.futures as cf
import copy
import json
import math
import os
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "ai_training"
GODOT = os.environ.get("GODOT", "godot")
WORKERS = int(os.environ.get("WORKERS", "4"))
SCENARIO = "res://data/scenarios/july_1914/"
DAYS = 400
SEEDS_PER_EVAL = 3
POP = 8          # candidates per generation (mirrored pairs: POP / 2 directions)
SIGMA0 = 0.12    # step size in the normalised [0, 1] space
SIGMA_DECAY = 0.985
LEARNING_RATE = 1.0

# (dotted path in data/ai.json, lowest, highest, integer?)
PARAMS = [
    ("offense.odds_bold", 0.5, 2.0, False), ("offense.odds_cautious", 0.8, 3.0, False),
    ("offense.max_share", 0.3, 1.0, False), ("offense.w_value", 0.0, 6.0, False), ("offense.w_score", 0.0, 6.0, False),
    ("offense.w_margin", 0.0, 2.5, False), ("offense.w_days", 0.0, 0.25, False), ("offense.w_supply", 0.0, 0.8, False),
    ("offense.w_plan", 0.0, 6.0, False), ("offense.min_utility", -1.0, 3.0, False),
    ("offense.max_campaigns", 1, 5, True), ("offense.retry_days", 1, 14, True), ("offense.gather_days", 8, 60, True),
    ("offense.fall_back_morale", 0.1, 0.8, False), ("offense.fall_back_ratio", 0.3, 1.5, False),
    ("offense.reinforce_weight", 0.0, 0.6, False), ("offense.front_keep", 0.05, 0.9, False),
    ("offense.gather_eta_share", 0.3, 1.0, False), ("offense.plan_odds_factor", 0.4, 1.0, False),
    ("defense.reserve_share", 0.0, 0.5, False), ("defense.reserve_stay", 1.0, 4.0, False),
    ("defense.rebalance_ratio", 1.1, 4.0, False), ("defense.merge_max_units", 3, 20, True),
    ("defense.retake_hops", 1, 7, True), ("defense.anchor_armies", 1, 10, True), ("defense.anchor_max", 1, 6, True),
    ("defense.anchor_days", 3, 90, True), ("defense.anchor_value_weight", 0.0, 400.0, False),
    ("defense.near_km", 100.0, 1000.0, False), ("defense.rebalance_max_km", 150.0, 1400.0, False),
    ("defense.plan_need", 1.0, 4.0, False), ("defense.settle_days", 0, 25, True),
    ("forces.war_multiplier", 1.2, 7.0, False), ("forces.per_turn", 1, 5, True), ("forces.max_training", 2, 12, True),
    ("forces.treasury_floor", 0.0, 20.0, False), ("forces.deficit_months", 0, 10, True),
    ("forces.income_share", 0.15, 1.5, False), ("forces.horizon_months", 1, 5, True),
    ("forces.mix.artillery", 0.03, 0.55, False), ("forces.mix.cavalry", 0.0, 0.25, False),
    ("peace.k_score", 0.2, 2.5, False), ("peace.k_support", 0.0, 5.0, False), ("peace.k_debt", 0.0, 12.0, False),
    ("peace.k_days_per_month", 0.0, 5.0, False), ("peace.capital_lost", 0.0, 100.0, False),
    ("peace.k_ally", 0.0, 40.0, False), ("peace.seek_threshold", 15.0, 100.0, False),
    ("peace.white_tolerance", 0.0, 60.0, False), ("peace.loss_floor", 0.0, 30.0, False),
    ("peace.accept_share", 0.1, 1.0, False), ("peace.demand_score", 5.0, 60.0, False),
    ("peace.aims_enough", 0.0, 1.0, False), ("peace.demand_budget_share", 0.3, 1.0, False),
    ("peace.indemnity_max_share", 0.0, 0.5, False), ("peace.k_quiet", 0.0, 14.0, False),
    ("peace.quiet_grace_months", 1, 12, True),
    # The gold economy's building weights, and sending men home.
    ("budget.factory_war", 0.0, 1.0, False), ("budget.port_want", 0.0, 0.5, False),
    ("budget.front_railway", 0.0, 2.0, False), ("budget.front_works", 0.5, 5.0, False),
    ("forces.demob_after_days", 30, 720, True), ("forces.demob_margin", 1.0, 1.6, False), ("forces.demob_share", 0.05, 0.6, False),
]


def read_ai(path=None) -> dict:
    if path is None:
        return json.loads((ROOT / "data" / "ai.json").read_text())
    return json.loads(path.read_text())


def lookup(cfg: dict, path: str):
    node = cfg
    for key in path.split("."):
        node = node[key]
    return node


def to_unit(value, lo, hi) -> float:
    return min(1.0, max(0.0, (float(value) - lo) / (hi - lo)))


def from_unit(x, lo, hi, integer):
    v = lo + min(1.0, max(0.0, x)) * (hi - lo)
    return int(round(v)) if integer else round(v, 4)


def theta_to_values(theta: list) -> dict:
    """Normalised parameters -> {dotted path: number} (with the infantry share filling what guns and horse leave)."""
    values = {}
    for x, (path, lo, hi, integer) in zip(theta, PARAMS):
        values[path] = from_unit(x, lo, hi, integer)
    values["forces.mix.infantry"] = round(max(0.05, 1.0 - values["forces.mix.artillery"] - values["forces.mix.cavalry"]), 4)
    return values


def initial_theta(cfg: dict) -> list:
    return [to_unit(lookup(cfg, p), lo, hi) for p, lo, hi, _ in PARAMS]


# ---------------------------------------------------------------------------------------------- games

def play(job: dict, tag: str) -> dict:
    jobfile = OUT / "jobs" / f"{tag}.json"
    jobfile.parent.mkdir(parents=True, exist_ok=True)
    jobfile.write_text(json.dumps(job))
    for attempt in range(2):
        try:
            res = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "-s", "res://tools/ai_arena.gd", "--", str(jobfile)],
                                 capture_output=True, text=True, timeout=400)
            for line in res.stdout.splitlines():
                if line.startswith("RESULT "):
                    jobfile.unlink(missing_ok=True)
                    return json.loads(line[7:])
        except subprocess.TimeoutExpired:
            pass
    return {"scores": {}, "battles": 0, "wars": 0}


def groups_for(seed: int, nations: list) -> tuple:
    rng = random.Random(seed)
    shuffled = sorted(nations)
    rng.shuffle(shuffled)
    half = len(shuffled) // 2
    return shuffled[:half], shuffled[half:]


def matches(candidate: dict, baseline: dict, seeds: list, nations: list, prefix: str):
    """The jobs of one evaluation: for each seed the nations are split in two and play both ways round."""
    jobs = []
    for seed in seeds:
        a, b = groups_for(seed, nations)
        for flip, group in enumerate((a, b)):
            jobs.append(({"scenario": SCENARIO, "days": DAYS, "seed": seed, "group_a": group, "candidate": candidate,
                          "baseline": baseline, "start": "blocs"}, f"{prefix}_{seed}_{flip}", group))
    return jobs


def advantage(results: list, nations: list) -> float:
    """Mean over seeds of the summed gain of the candidate's nations over the same nations under the baseline."""
    by_seed = {}
    for (job, _tag, group), res in results:
        by_seed.setdefault(job["seed"], []).append((group, res["scores"]))
    total = 0.0
    for seed, runs in by_seed.items():
        (g1, s1), (g2, s2) = runs[0], runs[1]       # run 1: g1 plays the candidate; run 2: g2 plays it
        diff = 0.0
        for n in nations:
            if n in g1:
                diff += s1.get(n, 0.0) - s2.get(n, 0.0)
            else:
                diff += s2.get(n, 0.0) - s1.get(n, 0.0)
        total += diff
    return total / max(len(by_seed), 1)


NATIONS = ["ALB", "AUH", "BEL", "BUL", "DEN", "ESP", "FRA", "GBR", "GER", "GRE", "ITA", "LUX", "MNE", "NED", "NOR",
           "OTT", "POR", "ROM", "RUS", "SRB", "SUI", "SWE"]


# ---------------------------------------------------------------------------------------------- training

def run(generations: int):
    OUT.mkdir(parents=True, exist_ok=True)
    state_file = OUT / "state.json"
    cfg = read_ai()
    if state_file.exists():
        state = json.loads(state_file.read_text())
    else:
        state = {"gen": 0, "sigma": SIGMA0, "theta": initial_theta(cfg), "theta0": initial_theta(cfg)}
    n = len(PARAMS)
    pool = cf.ThreadPoolExecutor(max_workers=WORKERS)
    for _ in range(generations):
        gen = state["gen"]
        rng = random.Random(1000 + gen)
        sigma = state["sigma"]
        theta = state["theta"]
        eps = [[rng.gauss(0, 1) for _ in range(n)] for _ in range(POP // 2)]
        cands = []
        for e in eps:
            cands.append([min(1.0, max(0.0, t + sigma * x)) for t, x in zip(theta, e)])
            cands.append([min(1.0, max(0.0, t - sigma * x)) for t, x in zip(theta, e)])
        seeds = [100 * gen + k + 1 for k in range(SEEDS_PER_EVAL)]
        baseline = theta_to_values(theta)
        started = time.time()
        all_jobs = []
        for i, c in enumerate(cands):
            for job, tag, group in matches(theta_to_values(c), baseline, seeds, NATIONS, f"g{gen}c{i}"):
                all_jobs.append((i, job, tag, group))
        futures = [(i, job, tag, group, pool.submit(play, job, tag)) for i, job, tag, group in all_jobs]
        per_cand = {i: [] for i in range(len(cands))}
        for i, job, tag, group, fut in futures:
            per_cand[i].append(((job, tag, group), fut.result()))
        fit = [advantage(per_cand[i], NATIONS) for i in range(len(cands))]
        # rank-weighted step: centred ranks as utilities
        order = sorted(range(len(cands)), key=lambda i: fit[i])
        util = [0.0] * len(cands)
        for rank, i in enumerate(order):
            util[i] = rank / (len(cands) - 1) - 0.5
        step = [0.0] * n
        for k in range(POP // 2):
            u = util[2 * k] - util[2 * k + 1]            # the + candidate against its mirror
            for j in range(n):
                step[j] += u * eps[k][j]
        new_theta = [min(1.0, max(0.0, t + LEARNING_RATE * sigma * s / (POP / 2))) for t, s in zip(theta, step)]
        state.update({"gen": gen + 1, "sigma": sigma * SIGMA_DECAY, "theta": new_theta})
        state_file.write_text(json.dumps(state))
        with open(OUT / "history.jsonl", "a") as f:
            f.write(json.dumps({"gen": gen, "sigma": round(sigma, 4), "fitness": [round(x, 3) for x in fit],
                                "best": round(max(fit), 3), "mean": round(sum(fit) / len(fit), 3), "seeds": seeds,
                                "secs": round(time.time() - started)}) + "\n")
        print(f"gen {gen}: fitness mean {sum(fit) / len(fit):+.3f} best {max(fit):+.3f} ({time.time() - started:.0f}s)", flush=True)


def test(games: int):
    """The trained numbers against the numbers the training started from, on seeds it never saw."""
    state = json.loads((OUT / "state.json").read_text())
    trained = theta_to_values(state["theta"])
    start = theta_to_values(state["theta0"])
    seeds = [90000 + k for k in range(games)]
    pool = cf.ThreadPoolExecutor(max_workers=WORKERS)
    jobs = matches(trained, start, seeds, NATIONS, "test")
    futures = [(job, tag, group, pool.submit(play, job, tag)) for job, tag, group in jobs]
    results = [((job, tag, group), fut.result()) for job, tag, group, fut in futures]
    per_seed = []
    for seed in seeds:
        mine = [r for r in results if r[0][0]["seed"] == seed]
        per_seed.append(advantage(mine, NATIONS))
    mean = sum(per_seed) / len(per_seed)
    sd = math.sqrt(sum((x - mean) ** 2 for x in per_seed) / max(len(per_seed) - 1, 1))
    wins = sum(1 for x in per_seed if x > 0)
    print(f"trained vs start over {games} fresh seeds: mean advantage {mean:+.3f} (se {sd / math.sqrt(len(per_seed)):.3f}), "
          f"better in {wins} of {games}; per seed {[round(x, 2) for x in per_seed]}")


def _skip_string(text: str, i: int) -> int:
    """Index just past the string that starts at text[i] (a double quote)."""
    i += 1
    while text[i] != '"':
        i += 2 if text[i] == "\\" else 1
    return i + 1


def _find_value(text: str, keys: list) -> tuple:
    """The span (start, end) of the number at a dotted path in a JSON text, found by walking the braces so that a
    key of the same name in another object cannot be taken for it."""
    lo, hi = 0, len(text)
    for depth, key in enumerate(keys):
        i = lo
        level = 0
        found = None
        while i < hi:
            c = text[i]
            if c == '"':
                end = _skip_string(text, i)
                if level == 1 and text[i + 1:end - 1] == key:
                    j = end
                    while text[j] in " \t\r\n":
                        j += 1
                    if text[j] == ":":
                        found = j + 1
                        break
                i = end
                continue
            if c in "{[":
                level += 1
            elif c in "}]":
                level -= 1
                if level == 0:
                    break
            i += 1
        if found is None:
            raise KeyError(".".join(keys))
        while text[found] in " \t\r\n":
            found += 1
        if depth == len(keys) - 1:
            end = found
            while end < len(text) and text[end] in "-+.0123456789eE":
                end += 1
            if end == found:
                raise ValueError(".".join(keys) + " is not a number")
            return found, end
        # the next key is looked for inside this object
        lo = found
        i = lo
        level = 0
        while i < len(text):
            if text[i] == '"':
                i = _skip_string(text, i)
                continue
            if text[i] in "{[":
                level += 1
            elif text[i] in "}]":
                level -= 1
                if level == 0:
                    hi = i + 1
                    break
            i += 1
        # `level` was counted from the object's own brace, so the scan above starts at it
    raise KeyError(".".join(keys))


def rewrite_values(text: str, values: dict) -> str:
    """The text of data/ai.json with these dotted-path numbers replaced, and nothing else changed (the file keeps its
    layout and its notes)."""
    for path, v in values.items():
        start, end = _find_value(text, path.split("."))
        text = text[:start] + str(v) + text[end:]
    json.loads(text)
    return text


def apply(state_path=None, ai_path=None):
    state = json.loads((state_path or OUT / "state.json").read_text())
    values = theta_to_values(state["theta"])
    ai_path = ai_path or ROOT / "data" / "ai.json"
    ai_path.write_text(rewrite_values(ai_path.read_text(), values))
    print("wrote", len(values), "numbers to", ai_path)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "run"
    if cmd == "run":
        run(int(sys.argv[2]) if len(sys.argv) > 2 else 10)
    elif cmd == "test":
        test(int(sys.argv[2]) if len(sys.argv) > 2 else 8)
    elif cmd == "apply":
        apply()
