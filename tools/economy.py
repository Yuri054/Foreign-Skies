"""Runs tools/economy_policies.gd for a grid of nations and economic policies at once and prints, per nation, a
Markdown table of where each policy leaves the economy, against doing nothing: what step 3 of PLAN.md is judged by.
Run: python tools/economy.py [--tags GER,ITA,BEL,SRB] [--years 14] [--policies passive,fact,...] [--workers 4] [--out FILE]
Set GODOT to the Godot executable if it is not on the PATH. The AI is off in these runs (no AI wars), so the numbers
are the economy alone."""
import argparse, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot = os.environ.get("GODOT", "godot")
POLICIES = "passive,fact,rail,port,all,focus,all+focus,tax=0.05,tax=0.2,tax=0.4,mob=0.4,arms=0+all,arms=0.2+all,army,build=1904,build=1908"


def run(tag, years, policy):
    command = [godot, "--headless", "--path", root, "-s", "res://tools/economy_policies.gd", "--", tag, str(years),
               policy.replace("+", ",")]
    out = subprocess.run(command, capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.startswith("RESULT "):
            r = json.loads(line[len("RESULT "):])
            r["policy"] = policy
            return r
    return {"tag": tag, "policy": policy, "error": "no result"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--tags", default="GER,ITA,BEL,SRB")
    p.add_argument("--years", type=int, default=14)
    p.add_argument("--policies", default=POLICIES)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--out")
    a = p.parse_args()
    started = time.time()
    jobs = [(t, pol) for t in a.tags.split(",") for pol in a.policies.split(",")]
    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        results = list(pool.map(lambda j: run(j[0], a.years, j[1]), jobs))
    lines = ["Economy policies, %d years from the scenario's start (%.0f s)" % (a.years, time.time() - started)]
    for tag in a.tags.split(","):
        rows = [r for r in results if r["tag"] == tag]
        base = next((r for r in rows if r["policy"] == "passive" and "error" not in r), None)
        lines += ["", "**%s**" % tag, "",
                  "| Policy | GDP/mo | vs nothing | IC/day | vs nothing | Revenue/mo | Net/mo | Treasury | Development | Support | Built | Shells (days of war) | Divisions | Rank by decade | Leaders |",
                  "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for r in rows:
            if "error" in r:
                lines.append("| %s | error |" % r["policy"])
                continue
            vs_gdp = "%+.0f%%" % ((r["gdp"] / base["gdp"] - 1) * 100) if base else "-"
            vs_ic = "%+.0f%%" % ((r["ic"] / base["ic"] - 1) * 100) if base else "-"
            built = sum(r["built"].values()) if r["built"] else 0
            lines.append("| %s | %.1f | %s | %.0f | %s | %.2f | %+.2f | %d | %+.0f%% | %d | %d | %s | %s | %s | %s |" % (
                r["policy"], r["gdp"], vs_gdp, r["ic"], vs_ic, r["revenue"], r["net"], r["treasury"],
                r["development"] * 100, r["war_support"], built, r.get("stock_days", "-"), r.get("divisions", "-"),
                " ".join(str(x) for x in r.get("ranks", [])) + " → %s" % r.get("rank", "-"), ", ".join(r.get("leaders", []))))
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
