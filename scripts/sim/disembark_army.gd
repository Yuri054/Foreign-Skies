class_name DisembarkArmy
extends Command
## Puts an embarked army ashore: in the port its fleet lies in, or from the sea in a coastal
## province that opens on the fleet's zone (an assault if the enemy holds it).

var tag: String
var army_id: int
var province: int


func _init(p_tag := "", p_army := 0, p_province := 0) -> void:
	tag = p_tag
	army_id = p_army
	province = p_province


func execute(gs: Node) -> bool:
	var a: Army = gs.armies.get(army_id)
	if a == null or a.tag != tag or not a.embarked():
		return false
	var f: Fleet = gs.fleets.get(a.fleet_id)
	if f == null or f.tag != tag or province < 1 or province >= gs.province_owner.size():
		return false
	if not Military.can_enter(gs, tag, province):
		return false
	if f.is_in_port():
		if f.port != province or f.is_moving():
			return false
		Navy.land_army(gs, a, province, false)
	else:
		if f.is_moving() or not MapData.zones_of_port(province).has(f.zone):
			return false
		Navy.land_army(gs, a, province, true)
	return true


func to_dict() -> Dictionary:
	return {"type": "DisembarkArmy", "tag": tag, "army": army_id, "province": province}


func changes_economy() -> bool:
	return false
