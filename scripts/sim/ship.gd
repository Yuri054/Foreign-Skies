class_name Ship
extends RefCounted
## One squadron of a fleet (a handful of hulls). Strength is the share of it still afloat
## and fit to fight; morale is 0..1.

var type: String
var strength := 1.0
var morale := 1.0


func _init(p_type := "destroyer", p_strength := 1.0) -> void:
	type = p_type
	strength = p_strength


func def() -> Dictionary:
	return Navy.cfg.types[type]


## Fighting value: the type's attack, scaled by strength and dulled by low morale.
func power() -> float:
	return def().attack * strength * lerpf(Military.cfg.combat.morale_floor_effect, 1.0, morale)


## Men this squadron can carry overseas.
func capacity() -> int:
	return int(def().capacity * strength)


func to_dict() -> Dictionary:
	return {"type": type, "strength": strength, "morale": morale}
