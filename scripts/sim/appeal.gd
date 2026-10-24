class_name Appeal
extends Command
## A nation's public stand on Europe's tension: an appeal for calm (cools it) or sabre-rattling (heats it, for
## prestige and war support). Costs diplomacy points and cannot be repeated for a while. See Pressure.appeal.

var tag: String
var kind: String


func _init(p_tag := "", p_kind := "calm") -> void:
	tag = p_tag
	kind = p_kind


func execute(gs: Node) -> bool:
	return Pressure.appeal(gs, tag, kind)


func to_dict() -> Dictionary:
	return {"type": "Appeal", "tag": tag, "kind": kind}
