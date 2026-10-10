class_name Scenarios
extends RefCounted
## The scenarios the game can start: every folder under data/scenarios/ with a scenario.json.
## The main menu lists them; the scenario file carries what the list shows (name, description,
## start_date, playable, thumbnail). It also carries what the menu hands to the map scene.

const ROOT := "res://data/scenarios/"

## Set by the menu when a game is loaded or continued: the map scene then skips the nation
## picker and plays on as the saved game's nation. Cleared by the map scene once read.
static var resume := false


## [{dir, name, description, start_date: "28 July 1914", playable, thumbnail}], by folder name.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(ROOT)
	folders.sort()
	for folder in folders:
		var dir := "%s%s/" % [ROOT, folder]
		var path := dir + "scenario.json"
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		var d: Array = data.get("start_date", [])
		var thumb: String = data.get("thumbnail", "")
		out.append({
			"dir": dir,
			"name": str(data.get("name", folder)),
			"description": str(data.get("description", "")),
			"start_date": "%d %s %d" % [d[2], Clock.MONTH_NAMES[d[1] - 1], d[0]] if d.size() == 3 else "",
			"playable": bool(data.get("playable", true)),
			"thumbnail": dir + thumb if not thumb.is_empty() else "",
		})
	return out
