"""Runs tools/campaign_report.gd over many seeds at once and prints the results as a Markdown table, one row a seed and
a row of medians: the measurements PLAN.md's steps are judged by.
Run: python tools/campaign.py [--scenario jan_1900] [--years 20] [--seeds 0-9] [--bystander ESP] [--workers 4] [--out FILE]
Set GODOT to the Godot executable if it is not on the PATH. --seeds takes a range (0-9) or a list (0,3,7). --out also
writes the table, and the raw results as JSON lines next to it (FILE.jsonl)."""
import argparse, json, os, statistics, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot = os.environ.get("GODOT", "godot")

COLUMNS = [
    ("seed", "Seed"),
    ("first_gp_war", "First GP war"),
    ("general_war", "General war"),
    ("neutral_attacks_early", "Neutrals attacked before 1912"),
    ("crisis_min_odds", "Weakest crisis odds"),
    ("gp_war_months_median", "GP war months (median)"),
    ("fra_ger_months", "FRA-GER months"),
    ("capitals_ceded", "Capitals ceded"),
    ("detached_ceded", "Detached cessions"),
    ("sea_ceded", "Ceded by sea"),
    ("worst_gp_loss", "Worst GP loss"),
    ("post_wars_per_year", "Wars/yr from 1922"),
    ("post_crises_per_year", "Crises/yr from 1922"),
    ("post_tension_sd", "Tension SD from 1922"),
    ("treasury_months", "Treasury (months)"),
    ("treasury_months_late", "Treasury from 1922"),
    ("demob_ratio", "Army / last war peak"),
    ("focus_idle_max", "Longest idle focus"),
    ("bystander_decisions", "Bystander decisions/yr"),
]
MEDIAN_KEYS = [k for k, _ in COLUMNS if k not in ("seed", "fra_ger_months")]


def seeds_of(text):
    if "-" in text:
        a, b = text.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(s) for s in text.split(",")]


def run(scenario, years, seed, bystander):
    command = [godot, "--headless", "--path", root, "-s", "res://tools/campaign_report.gd", "--",
               "res://data/scenarios/%s/" % scenario, str(years), str(seed), bystander]
    out = subprocess.run(command, capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.startswith("RESULT "):
            return json.loads(line[len("RESULT "):])
    errors = [l for l in (out.stdout + out.stderr).splitlines() if "SCRIPT ERROR" in l][:3]
    return {"seed": seed, "error": "; ".join(errors) or "no result"}


def cell(value):
    if value is None:
        return "-"
    if isinstance(value, list):
        return ", ".join("%g" % v for v in value) if value else "-"
    if isinstance(value, float):
        return "%g" % value
    return str(value)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--scenario", default="jan_1900")
    p.add_argument("--years", type=int, default=20)
    p.add_argument("--seeds", default="0-9")
    p.add_argument("--bystander", default="ESP")
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--out")
    a = p.parse_args()
    started = time.time()
    seeds = seeds_of(a.seeds)
    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        results = list(pool.map(lambda s: run(a.scenario, a.years, s, a.bystander), seeds))
    lines = ["%s, %d years, seeds %s, bystander %s (%.0f s)" % (a.scenario, a.years, a.seeds, a.bystander, time.time() - started), "",
             "| " + " | ".join(h for _, h in COLUMNS) + " |", "|" + "---|" * len(COLUMNS)]
    for r in results:
        if "error" in r:
            lines.append("| %s | error: %s |" % (r["seed"], r["error"]))
            continue
        lines.append("| " + " | ".join(cell(r.get(k)) for k, _ in COLUMNS) + " |")
    medians = []
    for k, _ in COLUMNS:
        if k == "seed":
            medians.append("**median**")
            continue
        values = [r[k] for r in results if "error" not in r and isinstance(r.get(k), (int, float)) and not isinstance(r.get(k), bool)]
        if k in ("first_gp_war", "general_war"):
            values = [v for v in values if v > 0]
        medians.append(cell(statistics.median(values)) if values and k in MEDIAN_KEYS else "")
    lines.append("| " + " | ".join(medians) + " |")
    text = "\n".join(lines)
    print(text)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        with open(a.out + ".jsonl", "w", encoding="utf-8") as f:
            for r in results:
                f.write(json.dumps(r) + "\n")
    return 1 if any("error" in r for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
