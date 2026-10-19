extends SceneTree
## Headless test of the clock's pace: the speeds come from data/clock.json, each speed is
## slower than the next, the default is speed 3, and speed 5 stays the fast-forward.
## Run: godot --headless --path . -s res://tests/clock_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var clock: Node = root.get_node("Clock")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clock.json"))
	_check(clock.seconds_per_day.size() == 5 and cfg.seconds_per_day.size() == 5, "five speeds")
	var same := true
	for i in 5:
		same = same and is_equal_approx(clock.seconds_per_day[i], float(cfg.seconds_per_day[i]))
	_check(same, "the speeds are the ones in data/clock.json (%s)" % str(clock.seconds_per_day))
	var ordered := true
	for i in 4:
		ordered = ordered and clock.seconds_per_day[i] > clock.seconds_per_day[i + 1]
	_check(ordered, "each speed is faster than the one before")
	_check(clock.seconds_per_day[2] >= 0.4, "the default speed takes at least 0.4 s a day, a month in 12 s")
	_check(clock.seconds_per_day[4] <= 0.05, "speed 5 is still the fast-forward")
	_check(clock.speed == int(cfg.default_speed), "the clock starts at the default speed (%d)" % clock.speed)
	clock.speed = 9
	_check(clock.speed == 5, "a speed past the top is held at 5")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
