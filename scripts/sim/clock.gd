extends Node
## Game calendar. Runs in real time with pause and five speeds; emits tick signals
## that every simulation system hangs off.

signal day_ticked
signal month_ticked
signal year_ticked
signal date_changed
signal speed_changed(speed: int)
signal pause_changed(paused: bool)

const CONFIG_PATH := "res://data/clock.json"

## Real seconds per game day at speeds 1..5 (data/clock.json overrides these).
var seconds_per_day: Array[float] = [2.0, 1.0, 0.5, 0.25, 0.025]
const MONTH_NAMES: PackedStringArray = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

var year := 1914
var month := 7
var day := 28
var paused := true : set = set_paused
var speed := 3 : set = set_speed

## Days since the scenario started (for durations).
var days_elapsed := 0

var _elapsed := 0.0


func _ready() -> void:
	load_config()


## Reads the speeds and the starting speed from data/clock.json; keeps the defaults if the file
## is missing or wrong.
func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (cfg is Dictionary):
		return
	var list: Variant = cfg.get("seconds_per_day", [])
	if list is Array and list.size() == seconds_per_day.size():
		for i in list.size():
			seconds_per_day[i] = maxf(0.005, float(list[i]))
	speed = int(cfg.get("default_speed", speed))


func start(y: int, m: int, d: int) -> void:
	year = y
	month = m
	day = d
	_elapsed = 0.0
	days_elapsed = 0
	date_changed.emit()


func _process(delta: float) -> void:
	if paused:
		return
	_elapsed += delta
	var step: float = seconds_per_day[speed - 1]
	# Bounded so a long frame at top speed cannot run away.
	var guard := 10
	while _elapsed >= step and guard > 0:
		_elapsed -= step
		guard -= 1
		advance_day()


func advance_day() -> void:
	var new_month := false
	var new_year := false
	day += 1
	days_elapsed += 1
	if day > days_in_month(year, month):
		day = 1
		month += 1
		new_month = true
		if month > 12:
			month = 1
			year += 1
			new_year = true
	date_changed.emit()
	day_ticked.emit()
	if new_month:
		month_ticked.emit()
	if new_year:
		year_ticked.emit()


func toggle_pause() -> void:
	paused = not paused


func set_paused(value: bool) -> void:
	# A join decision or peace offer waiting for the player holds time.
	if not value and GameState.has_pending():
		value = true
	paused = value
	pause_changed.emit(paused)


func set_speed(value: int) -> void:
	speed = clampi(value, 1, seconds_per_day.size())
	speed_changed.emit(speed)


func date_string() -> String:
	return "%d %s %d" % [day, MONTH_NAMES[month - 1], year]


## The date the given number of days from now, e.g. "14 August 1914".
func date_after(days: int) -> String:
	var y := year
	var m := month
	var d := day + days
	while d > days_in_month(y, m):
		d -= days_in_month(y, m)
		m += 1
		if m > 12:
			m = 1
			y += 1
	return "%d %s %d" % [d, MONTH_NAMES[m - 1], y]


static func days_in_month(y: int, m: int) -> int:
	match m:
		2:
			return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
		4, 6, 9, 11:
			return 30
	return 31
