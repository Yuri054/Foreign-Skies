class_name SetOffensive
extends Command
## Changes a plan of attack: "launch" (true or false: attack, or halt and go on planning), "aggressiveness"
## ("careful", "balanced" or "aggressive"), "phase" (adds a further line to reach once the last is taken: a list of
## provinces), "targets" (reshapes the line being fought for: a list of provinces) or "cancel".

var tag: String
var offensive_id: int
var key: String
var value: Variant


func _init(p_tag := "", p_id := 0, p_key := "", p_value: Variant = null) -> void:
	tag = p_tag
	offensive_id = p_id
	key = p_key
	value = p_value


func execute(gs: Node) -> bool:
	var o: Offensive = gs.offensives.get(offensive_id)
	if o == null or o.tag != tag:
		return false
	match key:
		"launch":
			o.active = bool(value) and not o.done
			if not o.active:
				o.launched = false
		"aggressiveness":
			if not Offensives.cfg().has(str(value)) or not str(value) in ["careful", "balanced", "aggressive"]:
				return false
			o.aggressiveness = str(value)
		"phase":
			if not value is Array or (value as Array).is_empty() or o.kind == "spearhead" and (value as Array).size() != 1:
				return false
			var line: Array[int] = []
			for p in value:
				line.append(int(p))
			o.phases.append(line)
			o.done = false
		"targets":
			if not value is Array or (value as Array).is_empty() or o.done or o.kind != "broad" and (value as Array).size() != 1:
				return false
			var line: Array[int] = []
			for p in value:
				if int(p) < 1 or int(p) >= gs.province_owner.size():
					return false
				line.append(int(p))
			o.phases[o.phase] = line
		"cancel":
			gs.offensives.erase(o.id)
		_:
			return false
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SetOffensive", "tag": tag, "offensive": offensive_id, "key": key, "value": value}


func changes_economy() -> bool:
	return false
