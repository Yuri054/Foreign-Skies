class_name MoveFleet
extends Command
## Orders a fleet to a sea zone, or into a port, by the cheapest route through the zones.
## Give a zone (port 0) or a port province (zone 0).

var tag: String
var fleet_id: int
var zone: int
var port: int
## The route the order found (filled in by execute).
var path: Array[int] = []


func _init(p_tag := "", p_fleet := 0, p_zone := 0, p_port := 0) -> void:
	tag = p_tag
	fleet_id = p_fleet
	zone = p_zone
	port = p_port


func execute(gs: Node) -> bool:
	var f: Fleet = gs.fleets.get(fleet_id)
	if f == null or f.tag != tag:
		return false
	var targets: Array = []
	if port > 0:
		if not Navy.can_dock(gs, tag, port):
			return false
		targets = MapData.zones_of_port(port)
	elif zone >= 1 and zone < MapData.sea_zones.size():
		targets = [zone]
	else:
		return false
	# Already there: the order cancels any sailing.
	if (port > 0 and f.port == port) or (port == 0 and f.zone == zone and f.port == 0):
		f.path.clear()
		f.entering = false
		f.dest_port = 0
		return true
	var starts: Array = MapData.zones_of_port(f.port) if f.is_in_port() else [f.zone]
	path = Navy.find_path(f.speed(), starts, targets)
	if path.is_empty():
		return false
	var route := path.duplicate()
	if not f.is_in_port() and route[0] == f.zone:
		route.pop_front()
	# Keep the progress already made if the fleet is still heading into the same zone.
	var keep_progress: bool = not f.is_in_port() and not f.path.is_empty() and not route.is_empty() and f.path[0] == route[0]
	f.retreating = false
	f.path.assign(route)
	f.dest_port = port
	f.entering = false
	if f.is_in_port():
		f.move_days_left = Navy.cfg.port_days
	elif f.path.is_empty():
		f.entering = port > 0
		f.move_days_left = Navy.cfg.port_days
	elif not keep_progress:
		f.move_days_left = Navy.zone_days(f.speed(), f.zone, f.path[0])
	gs.fleets_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"type": "MoveFleet", "tag": tag, "fleet": fleet_id, "zone": zone, "port": port}


func changes_economy() -> bool:
	return false
