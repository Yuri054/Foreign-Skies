class_name Army
extends RefCounted
## A stack of units under one general, standing in a province. Orders are a path of
## province ids; the army walks it one province at a time.

var id := 0
var tag := ""
var display_name := ""
var units: Array[Unit] = []
var province := 0
## Provinces still to enter, nearest first.
var path: Array[int] = []
## Days left before the army arrives in path[0].
var move_days_left := 0.0
## Days spent standing still; entrenchment grows with it.
var still_days := 0
## True while this army is the one that attacked in an ongoing battle.
var attacking := false
## The general in command (0 = none; see General and Military.set_general). The name and skill
## are copied from him so the rest of the code need not look him up.
var general_id := 0
var general_name := ""
var general_skill := 1.0
## Whether the army can draw supply (updated daily).
var supplied := true
## Set while the army is in a battle this day.
var fighting := false
## Marker symbol on the map: "auto" (by what the army is made of) or a key of "icons" in
## data/military.json.
var icon := "auto"
## Front this army is assigned to (0 = none).
var front_id := 0
## Army group this army belongs to (0 = none; see ArmyGroup).
var group_id := 0
## Fleet the army is embarked in (0 = on land). An embarked army stands in the port it left
## until it lands; it cannot fight, move or be supplied by land (see Navy).
var fleet_id := 0
## Days left in which a fresh landing fights at a penalty and has not dug in.
var landing_days := 0
## Days left in which the supplies that came ashore with the army last.
var landed_supply := 0


func embarked() -> bool:
	return fleet_id > 0


func men() -> float:
	var total := 0.0
	for u in units:
		total += u.men()
	return total


func power() -> float:
	var total := 0.0
	for u in units:
		total += u.power()
	var landing: float = Military.cfg.landing.power_mult if landing_days > 0 else 1.0
	var nation: Nation = GameState.nations.get(tag)
	var ready: float = Military.readiness_power(nation.army_ready) if nation != null else 1.0
	return total * general_skill * Military.marshal_mult(self) * landing * ready


## Mean morale, weighted by men.
func morale() -> float:
	var total := 0.0
	var weight := 0.0
	for u in units:
		total += u.morale * u.men()
		weight += u.men()
	return total / weight if weight > 0.0 else 0.0


## The marker symbol actually drawn: the chosen icon, or one picked from the army's makeup.
func shown_icon() -> String:
	if icon != "auto":
		return icon
	var men_by_type := {}
	for u in units:
		men_by_type[u.type] = men_by_type.get(u.type, 0.0) + u.men()
	var total := men()
	if total <= 0.0:
		return "infantry"
	if men_by_type.get("artillery", 0.0) > 0.35 * total:
		return "artillery"
	if men_by_type.get("cavalry", 0.0) > 0.5 * total:
		return "cavalry"
	return "infantry"


func entrenchment() -> int:
	if not path.is_empty() or landing_days > 0:
		return 0
	return mini(Military.cfg.combat.max_entrenchment, still_days / int(Military.cfg.combat.entrench_days_per_level))


func speed() -> float:
	var slowest := INF
	for u in units:
		slowest = minf(slowest, Military.cfg.unit_types[u.type].speed)
	return slowest


## How many units of each type the army holds, in the order of data/military.json; types it
## has none of are left out.
func composition() -> Dictionary:
	var out := {}
	for type in Military.unit_type_ids():
		var n := count_of(type)
		if n > 0:
			out[type] = n
	return out


func count_of(type: String) -> int:
	var n := 0
	for u in units:
		if u.type == type:
			n += 1
	return n


func to_dict() -> Dictionary:
	var list: Array = []
	for u in units:
		list.append(u.to_dict())
	return {"id": id, "tag": tag, "name": display_name, "province": province, "units": list,
			"general": general_name, "general_id": general_id, "skill": general_skill, "icon": icon, "front": front_id, "group": group_id, "fleet": fleet_id}
