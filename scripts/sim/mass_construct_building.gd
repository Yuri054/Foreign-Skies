class_name MassConstructBuilding
extends Command
## Queues one level of a building in many provinces at once: the best provinces first (see
## Economy.build_priority), until the province limit is reached or the gold queued would pass the
## limit. Each province is queued like a single ConstructBuilding.

var tag: String
var type: String
## Most provinces to build in.
var max_count: int
## Most gold to queue in total; 0 means no limit.
var max_spend: float
## Provinces that were built in; filled in by execute().
var built: Array[int] = []
## Gold and construction points they cost.
var gold := 0.0
var cp := 0.0
## Why the last run stopped: "all" (every eligible province), "count" or "spend".
var stopped_by := "all"


func _init(p_tag := "", p_type := "", p_max_count := 1000000, p_max_spend := 0.0) -> void:
	tag = p_tag
	type = p_type
	max_count = p_max_count
	max_spend = p_max_spend


func execute(gs: Node) -> bool:
	built.clear()
	gold = 0.0
	cp = 0.0
	stopped_by = "all"
	if not gs.nations.has(tag) or not Economy.cfg.buildings.has(type) or type.begins_with("_"):
		return false
	for id in Economy.mass_candidates(gs, tag, type):
		if built.size() >= max_count:
			stopped_by = "count"
			break
		var plan := Economy.build_plan(gs, id, type)
		if max_spend > 0.0 and gold + plan.gold > max_spend:
			stopped_by = "spend"
			break
		if not ConstructBuilding.new(tag, id, type).execute(gs):
			continue
		gold += plan.gold
		cp += plan.cp
		built.append(id)
	return not built.is_empty()


## What execute() would do right now, without changing anything: {count, gold, cp, stopped_by}.
func preview(gs: Node) -> Dictionary:
	if not gs.nations.has(tag):
		return {"count": 0, "gold": 0.0, "cp": 0.0, "stopped_by": "all"}
	var n: Nation = gs.nations[tag]
	var jobs := n.construction.duplicate(true)
	var treasury := n.treasury
	var points := n.cp
	execute(gs)
	var result := {"count": built.size(), "gold": gold, "cp": cp, "stopped_by": stopped_by}
	n.construction.clear()
	n.construction.append_array(jobs)
	n.treasury = treasury
	n.cp = points
	return result


func to_dict() -> Dictionary:
	return {"type": "MassConstructBuilding", "tag": tag, "building": type, "provinces": built.duplicate(), "gold": gold, "cp": cp}
