class_name ConvertFactory
extends Command
## Retools one factory of a province: a civilian one into a military one, or back. The old
## factory's output stops at once; the new one stands after `convert_days`, and the conversion
## costs `convert_cost_share` of a new factory (money only: the machinery is reused). The
## factory keeps its slot while it is being retooled.

var tag: String
var province: int
## The kind it becomes: "military_factory" or "factory".
var to_type: String
## Why it was refused, for the interface.
var reason := ""


func _init(p_tag := "", p_province := 0, p_to := "military_factory") -> void:
	tag = p_tag
	province = p_province
	to_type = p_to


## The kind that is retooled to produce `to_type`.
func from_type() -> String:
	return "factory" if to_type == "military_factory" else "military_factory"


static func cost_of(to: String) -> float:
	return Economy.cfg.buildings[to].cost * Economy.cfg.factories.convert_cost_share


func execute(gs: Node) -> bool:
	reason = ""
	if not gs.nations.has(tag) or to_type not in ["factory", "military_factory"]:
		reason = "Unknown nation or factory."
		return false
	if province < 1 or province >= gs.province_owner.size() or gs.province_owner[province] != tag:
		reason = "Not your province."
		return false
	if gs.province_controller[province] != tag:
		reason = "The province is occupied."
		return false
	var owned: Dictionary = gs.province_buildings[province]
	if owned.get(from_type(), 0) < 1:
		reason = "No %s to retool." % Economy.cfg.buildings[from_type()].name.to_lower()
		return false
	var n: Nation = gs.nations[tag]
	var cost := cost_of(to_type)
	if n.treasury < cost:
		reason = "Not enough money (£%.1fM)." % cost
		return false
	n.treasury -= cost
	owned[from_type()] -= 1
	if owned[from_type()] == 0:
		owned.erase(from_type())
	var days: int = Economy.cfg.factories.convert_days
	n.construction.append(Economy.new_job(province, to_type, days, true))
	return true


func to_dict() -> Dictionary:
	return {"type": "ConvertFactory", "tag": tag, "province": province, "to": to_type}
