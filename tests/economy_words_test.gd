extends SceneTree
## The resource economy is gone (docs/REWORK.md, R2): nothing the player reads may still speak of it. Reads every string
## a data file shows (data/*.json, keys starting with "_" are notes for the designer and skipped), every string literal
## of the scripts (labels, tooltips, news, the map's legends) and the player's guide (MANUAL.md), and fails on each
## word of the old economy it finds.
## Run: godot --headless --path . -s res://tests/economy_words_test.gd

const WORDS := ["IC", "coal", "iron", "timber", "raw material", "raw materials", "munition", "munitions", "shell", "shells",
		"deposit", "deposits", "famine", "food", "tax rate", "taxes", "tax income", "investment", "industrial capacity",
		"GBP", "arms share", "pop growth", "population growth"]
## Words that are fine where they stand: names and phrases that are not the old economy.
const ALLOWED := ["Hearts of Iron", "Iron Cross", "Iron Duke", "Iron Gate", "Iron Gates", "Iron Chancellor"]
const SKIP_SCRIPTS := ["res://tests/economy_words_test.gd"]

var _failures := 0
var _regex := RegEx.new()
var _string := RegEx.new()


func _initialize() -> void:
	var parts: PackedStringArray = []
	for w: String in WORDS:
		parts.append("\\b" + w.replace(" ", "\\s+") + "\\b")
	# "IC" only in capitals; the rest in any case.
	_regex.compile("(?i)(" + "|".join(parts.slice(1)) + ")|(?-i)\\bIC\\b|£")
	_string.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"):
			_walk_json(JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file)), "data/" + file)
	for dir in ["res://data/scenarios/july_1914", "res://data/scenarios/jan_1900"]:
		_walk_json(JSON.parse_string(FileAccess.get_file_as_string(dir + "/scenario.json")), dir.trim_prefix("res://") + "/scenario.json")
	for dir in ["res://scripts/ui", "res://scripts/map", "res://scripts/sim", "res://scripts/ai", "res://scripts"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") and not (dir + "/" + file) in SKIP_SCRIPTS:
				_scan_script(dir + "/" + file)
	var manual := FileAccess.get_file_as_string("res://MANUAL.md")
	var line_no := 0
	for line in manual.split("\n"):
		line_no += 1
		_check_text(line, "MANUAL.md:%d" % line_no)
	if _failures == 0:
		print("ok:   nothing the player reads speaks of the old economy")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _walk_json(v: Variant, where: String) -> void:
	if v is Dictionary:
		for k: String in v:
			if not k.begins_with("_"):
				_walk_json(v[k], where + "." + k)
	elif v is Array:
		for i in v.size():
			_walk_json(v[i], "%s[%d]" % [where, i])
	elif v is String:
		_check_text(v, where)


func _scan_script(path: String) -> void:
	var line_no := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line_no += 1
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		for m in _string.search_all(line):
			_check_text(m.get_string(1), "%s:%d" % [path.trim_prefix("res://"), line_no])


func _check_text(text: String, where: String) -> void:
	var clean := text
	for ok: String in ALLOWED:
		clean = clean.replace(ok, "")
	var m := _regex.search(clean)
	if m != null:
		_failures += 1
		printerr("FAIL: %s: \"%s\" in: %s" % [where, m.get_string(), text.substr(0, 160)])
