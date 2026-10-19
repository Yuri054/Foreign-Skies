class_name Unit
extends RefCounted
## One division (or artillery brigade). Strength is the share of its full size still fit to
## fight; morale is 0..1. It holds the equipment it carries (see "equipment" in
## data/military.json): category id -> amount.

var type: String
var strength := 1.0
var morale := 1.0
var equip: Dictionary = {}
## equip_factor() as of the last refresh_factor(); power() runs often (the AI), equipment seldom changes.
var factor := 1.0
## True on a day the nation's shell stockpile could not supply this unit's guns (see Military._burn_shells).
var shell_starved := false


func _init(p_type := "infantry", p_strength := 1.0) -> void:
	type = p_type
	strength = p_strength
	# A new unit is fully equipped; training and the stockpile decide otherwise (Military).
	if not Military.cfg.is_empty():
		for cat in needs():
			equip[cat] = float(needs()[cat]) * strength
	refresh_factor()


func full_size() -> int:
	return Military.cfg.unit_types[type].size


func men() -> float:
	return full_size() * strength


## What a full-strength unit of this type needs: category id -> amount.
func needs() -> Dictionary:
	return Military.cfg.unit_types[type].get("needs", {})


## What it needs now, for its present strength.
func need(cat: String) -> float:
	return float(needs().get(cat, 0.0)) * strength


## Held equipment over need, 0..1; 1 for a category the unit does not use.
func coverage(cat: String) -> float:
	var n := need(cat)
	return 1.0 if n <= 0.0 else minf(1.0, float(equip.get(cat, 0.0)) / n)


## The worst coverage over the categories it uses.
func coverage_min() -> float:
	var worst := 1.0
	for cat in needs():
		worst = minf(worst, coverage(cat))
	return worst


## Share of its power left after what it lacks: each category costs down to its floor.
func equip_factor() -> float:
	var f := 1.0
	for cat in needs():
		f *= lerpf(float(Military.cfg.equipment.categories[cat].floor), 1.0, coverage(cat))
	return f


func refresh_factor() -> void:
	factor = equip_factor()


## Equipment goes with the men: call after strength has been cut by `ratio` (new over old).
func lose_equipment(ratio: float) -> void:
	for cat in equip:
		equip[cat] *= clampf(ratio, 0.0, 1.0)
	refresh_factor()


## Takes what it lacks from `stock` (category -> amount, reduced in place), at most `limit` of
## its full need per category (a share, 0..1; 1 means no limit in practice).
func draw(stock: Dictionary, limit := 1.0) -> void:
	for cat in needs():
		var lack := need(cat) - float(equip.get(cat, 0.0))
		if lack <= 0.0:
			continue
		var take := minf(minf(lack, float(needs()[cat]) * limit), float(stock.get(cat, 0.0)))
		if take > 0.0:
			equip[cat] = float(equip.get(cat, 0.0)) + take
			stock[cat] = float(stock[cat]) - take
	refresh_factor()


## Fighting value: men in thousands times the type's attack, dulled by low morale and by
## missing equipment.
func power() -> float:
	var floor_effect: float = Military.cfg.combat.morale_floor_effect
	var shells := 1.0 - float(Military.cfg.combat.shell_penalty) if shell_starved else 1.0
	return men() / 1000.0 * Military.cfg.unit_types[type].attack * lerpf(floor_effect, 1.0, morale) * factor * shells


func to_dict() -> Dictionary:
	return {"type": type, "strength": strength, "morale": morale, "equip": equip}
