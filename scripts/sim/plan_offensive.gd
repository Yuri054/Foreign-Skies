class_name PlanOffensive
extends Command
## Gives an army a plan of attack (see Offensive): a broad push toward a target line (the provinces of its first phase)
## a spearhead at one province, or an invasion: the army gathers in a port and sails to land on a coastal province. It
## replaces any plan the army had. A detachment stands for its army.

const KINDS := ["broad", "spearhead", "invasion"]

var tag: String
var army_id: int
var kind: String
var provinces: Array[int]
var aggressiveness: String
## An invasion's port of embarkation (one of the nation's ports).
var port := 0
## Id of the new plan (filled in by execute).
var offensive_id := 0


func _init(p_tag := "", p_army := 0, p_kind := "broad", p_provinces: Array[int] = [], p_aggressiveness := "balanced", p_port := 0) -> void:
	port = p_port
	tag = p_tag
	army_id = p_army
	kind = p_kind
	provinces = p_provinces
	aggressiveness = p_aggressiveness


## Why the plan cannot be made, or "".
static func problem(gs: Node, p_tag: String, p_army: int, p_kind: String, line: Array[int], p_aggr: String, p_port := 0) -> String:
	var a: Army = gs.armies.get(p_army)
	if a == null or a.tag != p_tag:
		return "Choose one of your armies."
	if not KINDS.has(p_kind) or not (Offensives.cfg().has(p_aggr)):
		return "Unknown kind of attack."
	if line.is_empty() or (p_kind != "broad" and line.size() != 1):
		return "Mark the line to reach." if p_kind == "broad" else "Aim at one province."
	for p in line:
		if p < 1 or p >= gs.province_owner.size():
			return "Unknown province."
	if p_kind == "invasion":
		if p_port < 1 or p_port >= gs.province_owner.size() or gs.province_controller[p_port] != p_tag or not Navy.can_dock(gs, p_tag, p_port):
			return "Choose a port of yours to sail from."
		if MapData.zones_of_port(line[0]).is_empty():
			return "Choose a coastal province to land on."
		if not Military.can_enter(gs, p_tag, line[0]):
			return "You may not land there."
	return ""


func execute(gs: Node) -> bool:
	if not problem(gs, tag, army_id, kind, provinces, aggressiveness, port).is_empty():
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
	o.port = port
	gs.offensives[o.id] = o
	offensive_id = o.id
	gs.fronts_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "PlanOffensive", "tag": tag, "army": army_id, "kind": kind, "provinces": provinces, "aggressiveness": aggressiveness, "port": port}


func changes_economy() -> bool:
	return false
