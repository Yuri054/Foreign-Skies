"""Runs every headless test under tests/ and prints one line each, then a summary.
Run: python tools/run_tests.py [name ...]     (names without _test.gd run only those)
Set GODOT to the Godot executable if it is not on the PATH. Exit status is 1 if any test fails."""
import glob, os, subprocess, sys, time

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot = os.environ.get("GODOT", "godot")
wanted = set(sys.argv[1:])
failed = []
total = 0
for path in sorted(glob.glob(os.path.join(root, "tests", "*_test.gd"))):
    name = os.path.basename(path)[:-len("_test.gd")]
    if wanted and name not in wanted:
        continue
    total += 1
    start = time.time()
    try:
        out = subprocess.run([godot, "--headless", "--path", root, "-s", "res://tests/%s_test.gd" % name],
                             capture_output=True, text=True, timeout=400)
        text = out.stdout + out.stderr
        ok = out.returncode == 0 and not any(l.startswith("FAIL") and "FAILURES: 0" not in l for l in text.splitlines()) and "SCRIPT ERROR" not in text
        detail = [l for l in text.splitlines() if (l.startswith("FAIL") and "FAILURES: 0" not in l) or "SCRIPT ERROR" in l][:5]
    except subprocess.TimeoutExpired:
        ok, detail = False, ["timed out"]
    print("%-5s %-24s %5.1fs" % ("ok" if ok else "FAIL", name, time.time() - start), flush=True)
    if not ok:
        failed.append(name)
        for l in detail:
            print("      " + l, flush=True)
print("\n%d tests, %d failed%s" % (total, len(failed), (": " + ", ".join(failed)) if failed else ""))
sys.exit(1 if failed else 0)
