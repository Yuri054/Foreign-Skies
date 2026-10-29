class_name Unit
extends RefCounted
## One division (or artillery brigade). Strength is the share of its full size still fit to
## fight; morale is 0..1.

var type: String
var strength := 1.0
var morale := 1.0
## Drill from exercises, 0 to 1 (Military, military.json training): up to training.power_max more power.
var experience := 0.0


func _init(p_type := "infantry", p_strength := 1.0) -> void:
	type = p_type
	strength = p_strength


func full_size() -> int:
	return Military.cfg.unit_types[type].size


func men() -> float:
	return full_size() * strength


## Fighting value: men in thousands times the type's attack, dulled by low morale.
func power() -> float:
	var floor_effect: float = Military.cfg.combat.morale_floor_effect
	var drill := 1.0 + float(Military.cfg.get("training", {}).get("power_max", 0.0)) * experience
	return men() / 1000.0 * Military.cfg.unit_types[type].attack * lerpf(floor_effect, 1.0, morale) * drill


func to_dict() -> Dictionary:
	return {"type": type, "strength": strength, "morale": morale, "experience": experience}
