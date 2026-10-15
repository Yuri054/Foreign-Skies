class_name SaveGame
extends RefCounted
## Saving and loading the whole simulation. A save is a file under user://saves/: a header (a
## JSON text: version, date, nation, scenario) that a save list can read without
## parsing the rest, then the state as compressed Godot variant bytes (`var_to_bytes`), which keep
## the difference between whole numbers and fractions, dictionaries keyed by numbers and every bit
## of every float, none of which JSON or `var_to_str` do (a replay must come out the same). The
## state is plain data: objects of the sim classes become {"@o": class, "p": {...}}.
## Every field of GameState and of the sim classes is saved by name, so a new field is saved
## without touching this file; derived tables (output, caches) are rebuilt on load. Rules in
## GameState.save_game and load_game.

const VERSION := 1
## Where saves live; tests point it somewhere else.
static var dir := "user://saves/"
const EXT := ".sav"
const MAGIC := "godot-1914-save"
## GameState fields that are not saved: read again from the scenario, or worked out from the rest.
const SKIPPED := ["scenario", "scenario_dir", "economy_dirty", "autosave_enabled", "province_deposit", "province_gdp", "province_industry",
		"province_food", "province_pool", "owner_version"]
const CLASS_NAMES := ["Nation", "Army", "Unit", "Fleet", "Ship", "Front", "War", "Treaty", "General", "ArmyGroup", "AttackLine"]


## Everything in `gs` and the clock, as plain data.
static func snapshot(gs: Node) -> Dictionary:
	var state := {}
	for prop in gs.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.name in SKIPPED:
			continue
		state[prop.name] = _encode(gs.get(prop.name))
	return {
		"state": state,
		"clock": {"year": Clock.year, "month": Clock.month, "day": Clock.day, "days_elapsed": Clock.days_elapsed,
				"speed": Clock.speed},
	}


static func header(gs: Node, version := VERSION) -> Dictionary:
	var nation: Nation = gs.get_player()
	return {"magic": MAGIC, "version": version, "date": Clock.date_string(), "days": Clock.days_elapsed,
			"player": gs.player_tag, "nation": nation.display_name if nation != null else "",
			"scenario": gs.scenario_dir, "name": str(gs.scenario.get("name", ""))}


## Writes the game to `path`. Returns "" or what went wrong.
static func write(gs: Node, path: String, version := VERSION) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s." % path
	file.store_pascal_string(JSON.stringify(header(gs, version)))
	var bytes := var_to_bytes(snapshot(gs))
	file.store_64(bytes.size())
	file.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	file.close()
	# A save is replaced only once the new one is whole.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		return "Cannot write %s." % path
	return ""


## The header of a save, or {"error": text} if it is not one this version can read.
static func read_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open the save."}
	var line := file.get_pascal_string()
	file.close()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(line) == OK else null
	if not (parsed is Dictionary) or parsed.get("magic", "") != MAGIC:
		return {"error": "This is not a save of this game."}
	var version := int(parsed.get("version", 0))
	if version != VERSION:
		return {"error": "This save is from version %d of the save format; this game reads version %d." % [version, VERSION]}
	return parsed


## Reads a save into `gs`. Returns "" or what went wrong; a refused save changes nothing.
static func read(gs: Node, path: String) -> String:
	var head := read_header(path)
	if head.has("error"):
		return head.error
	var scenario_dir: String = head.get("scenario", "")
	if not FileAccess.file_exists(scenario_dir + "scenario.json"):
		return "The scenario of this save (%s) is not installed." % scenario_dir
	var file := FileAccess.open(path, FileAccess.READ)
	file.get_pascal_string()
	var size := file.get_64()
	var packed := file.get_buffer(file.get_length() - file.get_position())
	file.close()
	var body: Variant = null
	if size > 0 and size < 1 << 30:
		var bytes := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
		if bytes.size() == size:
			body = bytes_to_var(bytes)
	if not (body is Dictionary) or not body.has("state") or not body.has("clock"):
		return "The save is damaged."
	var state: Dictionary = body.state
	if state.get("province_owner", PackedStringArray()).size() != MapData.provinces.size():
		return "The save was made for a different map."

	gs.load_scenario(scenario_dir)
	for key: String in state:
		if key in SKIPPED or not (key in gs):
			continue
		_assign(gs, key, _decode(state[key]))
	var c: Dictionary = body.clock
	Clock.year = c.year
	Clock.month = c.month
	Clock.day = c.day
	Clock.days_elapsed = c.days_elapsed
	Clock.speed = c.speed
	Clock._elapsed = 0.0
	Clock.paused = true
	gs.finish_load()
	return ""


## The saves in a folder, newest first: [{path, file, header}] (unreadable ones carry an error).
static func list_saves(folder := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	folder = folder if not folder.is_empty() else dir
	if not DirAccess.dir_exists_absolute(folder):
		return out
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(EXT):
			continue
		var path := folder + file
		out.append({"path": path, "file": file.get_basename(), "header": read_header(path),
				"time": FileAccess.get_modified_time(path)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.time > y.time)
	return out


static func _assign(target: Object, key: String, value: Variant) -> void:
	var current: Variant = target.get(key)
	# Typed arrays keep their type: refill the one that is there.
	if current is Array and value is Array:
		current.clear()
		for item in value:
			current.append(item)
	elif current is Dictionary and value is Dictionary:
		current.clear()
		current.merge(value)
	else:
		target.set(key, value)


static func _encode(v: Variant) -> Variant:
	if v is Array:
		var list := []
		for item in v:
			list.append(_encode(item))
		return list
	if v is Dictionary:
		# Written as a list of keys and values: the variant writer sorts a dictionary's keys, and
		# the order of a dictionary decides who the AI moves first.
		var flat := []
		for k in v:
			flat.append(k)
			flat.append(_encode(v[k]))
		return {"@m": flat}
	if v is Object:
		var script: Script = v.get_script()
		var cls: String = script.get_global_name() if script != null else ""
		assert(cls in CLASS_NAMES, "Cannot save an object of class '%s'" % cls)
		var props := {}
		for prop in v.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				props[prop.name] = _encode(v.get(prop.name))
		return {"@o": cls, "p": props}
	return v


static func _decode(v: Variant) -> Variant:
	if v is Array:
		var list := []
		for item in v:
			list.append(_decode(item))
		return list
	if v is Dictionary:
		if v.has("@o"):
			return _decode_object(v)
		var out := {}
		var flat: Array = v["@m"]
		for i in range(0, flat.size(), 2):
			out[flat[i]] = _decode(flat[i + 1])
		return out
	return v


static func _decode_object(v: Dictionary) -> Object:
	var obj: Object
	match v["@o"]:
		"Nation":
			obj = Nation.new("", {"name": "", "color": Color.WHITE}, {})
		"Army":
			obj = Army.new()
		"Unit":
			obj = Unit.new()
		"Fleet":
			obj = Fleet.new()
		"Ship":
			obj = Ship.new()
		"Front":
			obj = Front.new()
		"War":
			obj = War.new()
		"Treaty":
			obj = Treaty.new()
		"General":
			obj = General.new()
		"ArmyGroup":
			obj = ArmyGroup.new()
		"AttackLine":
			obj = AttackLine.new()
		_:
			assert(false, "Unknown class in the save: %s" % v["@o"])
	for key: String in v.p:
		if key in obj:
			_assign(obj, key, _decode(v.p[key]))
	return obj
