class_name DemobilizeUnits
extends Command
## `tag` sends units home, in peace only: the men of each unit go back to the reserve (and from there, past what
## mobilization keeps, to the people at the month's end; see Economy.step_month), and their upkeep stops. `army_id` 0
## takes from every army; `count` is how many units, or -1 for "down to the peacetime army" (Nation.peacetime_army).
## Guns go last, and a unit in training is not touched.

var tag: String
var army_id: int
var count: int
## How many units went home.
var sent := 0


func _init(p_tag := "", p_army_id := 0, p_count := -1) -> void:
	tag = p_tag
	army_id = p_army_id
	count = p_count


func execute(gs: Node) -> bool:
	var n: Nation = gs.nations.get(tag)
	if n == null or not gs.wars_of(tag).is_empty():
		return false
	var armies: Array = []
	for a: Army in Military.armies_of(gs, tag):
		if (army_id == 0 or a.id == army_id) and not a.embarked():
			armies.append(a)
	if armies.is_empty():
		return false
	var excess := n.men_in_units - n.peacetime_army
	var to_send := count if count >= 0 else 1 << 30
	sent = 0
	# Infantry and cavalry first, the guns last; the largest armies give first.
	for pass_guns in [false, true]:
		armies.sort_custom(func(x: Army, y: Army) -> bool: return x.men() > y.men() or (x.men() == y.men() and x.id < y.id))
		for a: Army in armies:
			for i in range(a.units.size() - 1, -1, -1):
				if sent >= to_send or (count < 0 and excess <= 0):
					break
				var u: Unit = a.units[i]
				var guns: bool = Military.cfg.unit_types[u.type].get("guns", false)
				if guns != pass_guns:
					continue
				n.manpower += roundi(u.men())
				excess -= roundi(u.men())
				a.units.remove_at(i)
				sent += 1
	for a: Army in armies:
		if a.units.is_empty():
			gs.armies.erase(a.id)
	if sent == 0:
		return false
	Military.refresh_men(gs)
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "DemobilizeUnits", "tag": tag, "army": army_id, "count": count}
