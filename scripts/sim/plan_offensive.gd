class_name PlanOffensive
extends Command
## Gives an army a plan of attack (see Offensive): a broad push toward a target line (the provinces of its first phase)
## or a spearhead at one province. It replaces any plan the army had. A detachment stands for its army.

const KINDS := ["broad", "spearhead"]

var tag: String
var army_id: int
var kind: String
var provinces: Array[int]
var aggressiveness: String
## Id of the new plan (filled in by execute).
var offensive_id := 0


func _init(p_tag := "", p_army := 0, p_kind := "broad", p_provinces: Array[int] = [], p_aggressiveness := "balanced") -> void:
	tag = p_tag
	army_id = p_army
	kind = p_kind
	provinces = p_provinces
	aggressiveness = p_aggressiveness


## Why the plan cannot be made, or "".
static func problem(gs: Node, p_tag: String, p_army: int, p_kind: String, line: Array[int], p_aggr: String) -> String:
	var a: Army = gs.armies.get(p_army)
	if a == null or a.tag != p_tag:
		return "Choose one of your armies."
	if not KINDS.has(p_kind) or not (Offensives.cfg().has(p_aggr)):
		return "Unknown kind of attack."
	if line.is_empty() or (p_kind == "spearhead" and line.size() != 1):
		return "A spearhead aims at one province." if p_kind == "spearhead" else "Mark the line to reach."
	for p in line:
		if p < 1 or p >= gs.province_owner.size():
			return "Unknown province."
	return ""


func execute(gs: Node) -> bool:
	if not problem(gs, tag, army_id, kind, provinces, aggressiveness).is_empty():
		return false
	var root := FrontSolver.root_of(gs, gs.armies[army_id])
	for o: Offensive in gs.offensives.values().duplicate():
		if o.army_id == root.id:
			gs.offensives.erase(o.id)
	var o := Offensive.new()
	o.id = gs.next_offensive_id
	gs.next_offensive_id += 1
	o.tag = tag
	o.army_id = root.id
	o.kind = kind
	o.phases = [provinces.duplicate()]
	o.aggressiveness = aggressiveness
	gs.offensives[o.id] = o
	offensive_id = o.id
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "PlanOffensive", "tag": tag, "army": army_id, "kind": kind, "provinces": provinces, "aggressiveness": aggressiveness}


func changes_economy() -> bool:
	return false
