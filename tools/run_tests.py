"""Runs every test under tests/ and prints one line each, then a summary.
Run: python tools/run_tests.py [--windowed] [name ...]     (names without _test.gd run only those)
Most tests are headless. A test that needs a real window (mouse input is not dispatched without
one) says so with a line "## WINDOWED" at the top: it is skipped unless --windowed is given, and
then runs under a virtual display (xvfb-run) at 1280x720.
Set GODOT to the Godot executable if it is not on the PATH, and SPEED_TESTS=0 to skip the checks
on how long a day takes (a loaded machine is slower than the limits). Exit status is 1 if any
test fails."""
import glob, os, shutil, subprocess, sys, time

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot = os.environ.get("GODOT", "godot")
windowed = "--windowed" in sys.argv
wanted = set(a for a in sys.argv[1:] if not a.startswith("--"))
failed = []
total = 0
for path in sorted(glob.glob(os.path.join(root, "tests", "*_test.gd"))):
    name = os.path.basename(path)[:-len("_test.gd")]
    if wanted and name not in wanted:
        continue
    needs_window = "## WINDOWED" in open(path, encoding="utf-8").read(400)
    if needs_window and not windowed:
        print("%-5s %-24s (needs a window: run with --windowed)" % ("skip", name), flush=True)
        continue
    total += 1
    start = time.time()
    command = [godot, "--headless", "--path", root, "-s", "res://tests/%s_test.gd" % name]
    if needs_window:
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", godot, "--path", root, "--resolution", "1280x720",
                   "--rendering-driver", "opengl3", "-s", "res://tests/%s_test.gd" % name]
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=400)
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
