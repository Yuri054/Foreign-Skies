class_name SendOverseas
extends Command
## Loads armies standing in a fleet's port and sails them to a coastal province: the fleet
## takes the cheapest route through the sea zones and the armies land when it arrives (an
## assault if the enemy holds the coast). One order for embark, sail and land.

var tag: String
var fleet_id: int
var army_ids: Array[int]
var destination: int
## The sea route found (filled in by execute).
var path: Array[int] = []


func _init(p_tag := "", p_fleet := 0, p_armies: Array[int] = [], p_destination := 0) -> void:
	tag = p_tag
	fleet_id = p_fleet
	army_ids = p_armies
	destination = p_destination


## Why this cannot be done, or "" if it can.
static func problem(gs: Node, p_tag: String, p_fleet: int, p_armies: Array[int], p_destination: int) -> String:
	var f: Fleet = gs.fleets.get(p_fleet)
	if f == null or f.tag != p_tag or p_armies.is_empty():
		return "Invalid order."
	if p_destination < 1 or p_destination >= gs.province_owner.size() or MapData.zones_of_port(p_destination).is_empty():
		return "Choose a coastal province."
	if not Military.can_enter(gs, p_tag, p_destination):
		return "You may not land there."
	var need := 0.0
	for id in p_armies:
		var a: Army = gs.armies.get(id)
		if a == null or a.tag != p_tag or a.embarked():
			return "Invalid order."
		var why := Navy.embark_problem(gs, p_tag, a, f)
		if why != "" and why != "Not enough transports":
			return why
		need += a.men()
	if need > Navy.free_capacity(gs, f):
		return "Not enough transports"
	if Navy.find_path(f.speed(), MapData.zones_of_port(f.port), MapData.zones_of_port(p_destination)).is_empty():
		return "No sea route"
	return ""


func execute(gs: Node) -> bool:
	if not problem(gs, tag, fleet_id, army_ids, destination).is_empty():
		return false
	var f: Fleet = gs.fleets[fleet_id]
	path = Navy.find_path(f.speed(), MapData.zones_of_port(f.port), MapData.zones_of_port(destination))
	var move := MoveFleet.new(tag, fleet_id, path[-1])
	if not move.execute(gs):
		return false
	for id in army_ids:
		var a: Army = gs.armies[id]
		Military.leave_front(gs, a)
		a.fleet_id = f.id
		a.still_days = 0
	f.landing = destination
	gs.armies_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "SendOverseas", "tag": tag, "fleet": fleet_id, "armies": army_ids, "destination": destination}


func changes_economy() -> bool:
	return false
