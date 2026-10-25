class_name Difficulty
extends RefCounted
## Difficulty presets (data/difficulty.json): a preset retunes the AI nations and the crisis generator by multiplying some of
## their numbers, and gives no one anything the rules do not. The preset is `GameState.difficulty`, chosen when a game
## starts and saved with it; `apply` rebuilds the AI's and the crisis generator's numbers from their files and then scales them,
## so applying twice gives the same as once and "historical" gives the shipped numbers.

const CONFIG_PATH := "res://data/difficulty.json"
const DEFAULT := "historical"

static var cfg: Dictionary = {}


static func load_config() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(data is Dictionary, "difficulty.json is invalid")
	cfg = data


## The ids of the presets, in file order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in cfg.presets:
		out.append(id)
	return out


static func label(id: String) -> String:
	return cfg.presets.get(id, {}).get("label", id)


static func text(id: String) -> String:
	return cfg.presets.get(id, {}).get("text", "")


## Retunes the AI and the crisis generator for the game's difficulty (an unknown one counts as the default).
static func apply(gs: Node) -> void:
	if cfg.is_empty():
		load_config()
	if not cfg.presets.has(gs.difficulty):
		gs.difficulty = DEFAULT
	var preset: Dictionary = cfg.presets[gs.difficulty]
	AI.load_config()
	Crisis.load_config()
	for e: Dictionary in preset.get("ai", []):
		_change(AI.cfg, e)
	for e: Dictionary in preset.get("crisis", []):
		_change(Crisis.cfg, e)


## Applies one entry: multiplies the number at its dotted path (an integer stays one), or sets the value there.
static func _change(root: Dictionary, e: Dictionary) -> void:
	var node: Dictionary = root
	var keys: PackedStringArray = str(e.path).split(".")
	for i in keys.size() - 1:
		node = node[keys[i]]
	var leaf: String = keys[keys.size() - 1]
	if e.has("set"):
		node[leaf] = e.set
		return
	var v: Variant = node[leaf]
	node[leaf] = roundi(v * float(e.mul)) if v is int else v * float(e.mul)
