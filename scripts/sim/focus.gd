class_name Focus
extends RefCounted
## National focus trees: each nation works on one focus at a time (data/focus.json). A focus
## takes days, needs the foci it requires done, and then its effects apply: lasting ones (summed
## into Nation.focus_fx and read by Economy and Diplomacy) and one-off ones (prestige, points,
## money, war support, army size, relations, casus belli).

const CONFIG_PATH := "res://data/focus.json"
const PERSISTENT := ["gdp", "industry", "food", "trade", "growth", "diplomacy", "construction"]

static var cfg: Dictionary = {}
static var _trees: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "focus.json is invalid")
	_trees.clear()


## The foci of a nation's tree: its template's, then its own, each {id, name, desc, x, y, days,
## requires, effects, ai, ...}.
static func tree_of(tag: String) -> Array:
	if _trees.has(tag):
		return _trees[tag]
	var spec: Dictionary = cfg.nations.get(tag, {"template": "minor", "extra": []})
	var out: Array = []
	if spec.has("tree"):
		# A nation with a tree of its own (the great powers) uses it whole.
		out.append_array(spec.tree)
	else:
		out.append_array(cfg.templates[spec.template])
		out.append_array(spec.extra)
	_trees[tag] = out
	return out


static func find(tag: String, id: String) -> Dictionary:
	for f: Dictionary in tree_of(tag):
		if f.id == id:
			return f
	return {}


## Why a focus cannot be started now ("" if it can): unknown, done, active, busy or locked.
static func block(gs: Node, tag: String, id: String) -> String:
	var f := find(tag, id)
	if f.is_empty() or not gs.nations.has(tag):
		return "unknown"
	var n: Nation = gs.nations[tag]
	if id in n.focus_done:
		return "done"
	if f.get("repeatable", false) and int(n.focus_count.get(id, 0)) >= int(f.get("max", 1)):
		return "done"
	if n.provinces.is_empty():
		return "unknown"
	if not n.focus.is_empty():
		return "active" if n.focus.id == id else "busy"
	for req: String in f.requires:
		if req not in n.focus_done:
			return "locked"
	return ""


static func start(gs: Node, tag: String, id: String) -> bool:
	if block(gs, tag, id) != "":
		return false
	var f := find(tag, id)
	gs.nations[tag].focus = {"id": id, "days_left": int(f.days), "days_total": int(f.days)}
	gs.focus_changed.emit(tag)
	return true


## Drops the focus being worked on; its progress is lost.
static func cancel(gs: Node, tag: String) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null or n.focus.is_empty():
		return false
	n.focus = {}
	gs.focus_changed.emit(tag)
	return true


## Daily: the focus in hand moves a day on and applies its effects when it is done.
static func step_day(gs: Node) -> void:
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.focus.is_empty():
			continue
		n.focus.days_left -= 1
		if n.focus.days_left <= 0:
			complete(gs, tag)


static func complete(gs: Node, tag: String) -> void:
	var n: Nation = gs.nations[tag]
	var id: String = n.focus.id
	n.focus = {}
	if id in n.focus_done:
		return
	var f := find(tag, id)
	if f.is_empty():
		return  # a focus an older save knew and this tree does not
	if f.get("repeatable", false):
		n.focus_count[id] = int(n.focus_count.get(id, 0)) + 1
		if n.focus_count[id] >= int(f.get("max", 1)):
			n.focus_done.append(id)
	else:
		n.focus_done.append(id)
	var fx: Dictionary = f.effects
	apply_effects(gs, tag, fx)
	gs.focus_completed.emit(tag, id)
	gs.focus_changed.emit(tag)


static func apply_effects(gs: Node, tag: String, fx: Dictionary) -> void:
	var n: Nation = gs.nations[tag]
	var lasting := false
	for k: String in PERSISTENT:
		if fx.has(k):
			n.focus_fx[k] = n.focus_fx.get(k, 0.0) + float(fx[k])
			lasting = true
	if fx.has("prestige"):
		Diplomacy.gain_prestige(gs, tag, float(fx.prestige))
	if fx.has("points"):
		Diplomacy.gain(gs, tag, float(fx.points))
	if fx.has("treasury"):
		n.treasury += float(fx.treasury)
	if fx.has("war_support"):
		WarSupport.change(gs, tag, float(fx.war_support))
	if fx.has("army_size"):
		var extra := int(round(n.peacetime_army * float(fx.army_size)))
		n.peacetime_army += extra
		n.manpower += extra
	for pair: Array in fx.get("relation", []):
		if gs.nations.has(pair[0]):
			Diplomacy.change_relation(gs, tag, pair[0], float(pair[1]))
	for target: String in fx.get("claim", []):
		if gs.nations.has(target):
			gs.casus_belli.append({"holder": tag, "target": target, "kind": "national_claim",
					"expires_day": Clock.days_elapsed + int(Diplomacy.cfg.war.cb_years * 365)})
	if lasting:
		gs.economy_dirty = true


## A short line for what a focus does, for the interface.
static func effects_text(fx: Dictionary) -> String:
	var parts: PackedStringArray = []
	var names := {"gdp": "output", "industry": "industry", "food": "food", "trade": "trade", "growth": "growth"}
	for k in names:
		if fx.has(k):
			parts.append("%+.1f%% %s" % [float(fx[k]) * 100.0, names[k]] if k != "growth" else "%+.1f points a year of growth" % (float(fx[k]) * 100.0))
	if fx.has("diplomacy"):
		parts.append("%+.1f diplomacy points a month" % float(fx.diplomacy))
	if fx.has("construction"):
		parts.append("%+d IC a day" % int(fx.construction))
	if fx.has("prestige"):
		parts.append("%+d prestige" % int(fx.prestige))
	if fx.has("points"):
		parts.append("%+d diplomacy points" % int(fx.points))
	if fx.has("treasury"):
		parts.append("£%+.1fM" % float(fx.treasury))
	if fx.has("war_support"):
		parts.append("%+d war support" % int(fx.war_support))
	if fx.has("army_size"):
		parts.append("%+d%% peacetime army" % roundi(float(fx.army_size) * 100.0))
	for pair: Array in fx.get("relation", []):
		parts.append("%s regards us %+d" % [pair[0], int(pair[1])])
	for target: String in fx.get("claim", []):
		parts.append("a claim on %s" % target)
	return ", ".join(parts)
