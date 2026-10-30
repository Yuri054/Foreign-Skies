class_name Ambition
extends RefCounted
## The player's ambition: a direction chosen for the nation (data/ambitions.json), not a score. Its state is worked out
## each month and the History book records how it went. The state lives in GameState.ambition: {id, tag, since, state}.

const CONFIG_PATH := "res://data/ambitions.json"

static var cfg: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "ambitions.json is invalid")


static func _cfg() -> Dictionary:
	if cfg.is_empty():
		load_config()
	return cfg


## The ambitions open to `tag`, in the order of the data: [id].
static func offered(gs: Node, tag: String) -> Array[String]:
	var out: Array[String] = []
	if not gs.nations.has(tag):
		return out
	for id: String in _cfg().ambitions:
		match str(_cfg().ambitions[id].get("for", "all")):
			"minor":
				if tag in Pressure.GREAT:
					continue
			"claims":
				if _claimed(gs, tag).is_empty():
					continue
		out.append(id)
	return out


## Province ids of the nation's scenario claims.
static func _claimed(gs: Node, tag: String) -> Array[int]:
	var out: Array[int] = []
	for claim: Dictionary in gs.scenario.get("claims", []):
		if claim.holder == tag:
			for id: int in Diplomacy.claim_provinces(claim):
				if id not in out:
					out.append(id)
	return out


## The player takes up an ambition (or "" to give it up). The History book notes it.
static func choose(gs: Node, tag: String, id: String) -> bool:
	if tag != gs.player_tag or (id != "" and id not in offered(gs, tag)):
		return false
	var old: String = gs.ambition.get("id", "")
	if old == id:
		return false
	if old != "":
		History.note(gs, "ambition", "%s gives up its ambition: %s." % [gs.nations[tag].display_name, label(old).to_lower()])
	gs.ambition = {} if id == "" else {"id": id, "tag": tag, "since": Clock.year, "state": ""}
	if id != "":
		History.note(gs, "ambition", "%s sets itself an ambition: %s." % [gs.nations[tag].display_name, label(id).to_lower()])
		gs.ambition.state = status(gs).state
	return true


static func label(id: String) -> String:
	return str(_cfg().ambitions.get(id, {}).get("label", id))


## How the ambition stands: {state ("on course", "achieved", "lost" or "" for none), text}.
static func status(gs: Node) -> Dictionary:
	var id: String = gs.ambition.get("id", "")
	var tag: String = gs.ambition.get("tag", "")
	if id == "" or not gs.nations.has(tag):
		return {"state": "", "text": ""}
	var n: Nation = gs.nations[tag]
	var years: int = Clock.year - int(gs.ambition.get("since", Clock.year))
	match id:
		"keep_out":
			for w: War in gs.wars.values():
				if (w.a == tag and w.b in Pressure.GREAT) or (w.b == tag and w.a in Pressure.GREAT):
					return {"state": "lost", "text": "We are at war with %s." % gs.nations[w.b if w.a == tag else w.a].display_name}
			if str(gs.ambition.get("state", "")) == "lost":
				return {"state": "lost", "text": "We were drawn into a great power's war."}
			return {"state": "on course", "text": "Kept out of the powers' wars for %d years." % years}
		"unify":
			var ids := _claimed(gs, tag)
			var held := ids.filter(func(i: int) -> bool: return gs.province_owner[i] == tag).size()
			if held == ids.size() and not ids.is_empty():
				return {"state": "achieved", "text": "Every claimed province is ours."}
			return {"state": "on course", "text": "%d of %d claimed provinces are ours." % [held, ids.size()]}
		"great_power":
			var rank := 1
			for other: String in gs.nations:
				if other != tag and not gs.nations[other].provinces.is_empty() and float(gs.nations[other].budget.get("income", 0.0)) > float(n.budget.get("income", 0.0)):
					rank += 1
			var need := int(_cfg().ambitions.great_power.get("rank", 6))
			if rank <= need:
				return {"state": "achieved", "text": "Our output ranks %d in Europe." % rank}
			return {"state": "on course", "text": "Our output ranks %d in Europe; the powers are the first %d." % [rank, need]}
	return {"state": "", "text": ""}


## Monthly: a change in how the ambition stands goes into the History book. A lost "keep out" stays lost.
static func step_month(gs: Node) -> void:
	if gs.ambition.is_empty():
		return
	var s := status(gs)
	if s.state != str(gs.ambition.get("state", "")):
		var who: String = gs.nations[gs.ambition.tag].display_name if gs.nations.has(gs.ambition.tag) else gs.ambition.tag
		match s.state:
			"achieved":
				History.note(gs, "ambition", "%s achieves its ambition (%s): %s" % [who, label(gs.ambition.id).to_lower(), s.text])
			"lost":
				History.note(gs, "ambition", "%s's ambition fails (%s): %s" % [who, label(gs.ambition.id).to_lower(), s.text])
			"on course":
				History.note(gs, "ambition", "%s's ambition (%s) is in doubt again: %s" % [who, label(gs.ambition.id).to_lower(), s.text])
		gs.ambition.state = s.state
