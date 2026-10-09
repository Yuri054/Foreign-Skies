class_name Fleet
extends RefCounted
## A stack of ships under one flag. It stands in a port (`port` > 0, `zone` 0) or in a sea zone
## (`zone` > 0, `port` 0). Orders are a path of sea zones; the fleet sails it one zone at a
## time, and may end by entering a port.

var id := 0
var tag := ""
var display_name := ""
var ships: Array[Ship] = []
## Sea zone the fleet is in (the last one it reached while sailing); 0 in port.
var zone := 0
## Province id of the port the fleet is in; 0 at sea.
var port := 0
## Zones still to enter, nearest first.
var path: Array[int] = []
## Port to enter once the path is sailed (0 = stay at sea).
var dest_port := 0
## Days left before the fleet reaches path[0], or finishes entering or leaving a port.
var move_days_left := 0.0
## True while the fleet is making its way into dest_port.
var entering := false
## Province the fleet is carrying armies to: they land when it reaches a zone that province
## opens on (0 = none).
var landing := 0
## Standing orders, a key of "missions" in data/navy.json.
var mission := "station"
## Set while the fleet is in a battle this day.
var fighting := false
## True from the day a fleet is found by an enemy until it is no longer fighting; fleets in a
## fight need no new contact to go on.
var engaged := false
## True while a beaten fleet is making for port.
var retreating := false
## Days since the fleet left a port; beyond a ship's range its crews and hulls wear down.
var days_out := 0


func is_in_port() -> bool:
	return port > 0


func is_moving() -> bool:
	return not path.is_empty() or entering


func power() -> float:
	var total := 0.0
	for s in ships:
		total += s.power()
	return total


## Mean morale, weighted by strength.
func morale() -> float:
	var total := 0.0
	var weight := 0.0
	for s in ships:
		total += s.morale * s.strength
		weight += s.strength
	return total / weight if weight > 0.0 else 0.0


## Km per day of the slowest ship.
func speed() -> float:
	var slowest := INF
	for s in ships:
		slowest = minf(slowest, s.def().speed)
	return slowest if slowest < INF else 0.0


## Men the fleet's transports can carry.
func capacity() -> int:
	var total := 0
	for s in ships:
		total += s.capacity()
	return total


func count_of(type: String) -> int:
	var n := 0
	for s in ships:
		if s.type == type:
			n += 1
	return n


## How many squadrons of each type, in the order of data/navy.json; types it has none of are left out.
func composition() -> Dictionary:
	var out := {}
	for type in Navy.type_ids():
		var n := count_of(type)
		if n > 0:
			out[type] = n
	return out


## The sea zone the fleet counts as being in: its own, or the (first) zone its port opens on.
func current_zone() -> int:
	if zone > 0:
		return zone
	var zones := MapData.zones_of_port(port)
	return zones[0] if not zones.is_empty() else 0


func to_dict() -> Dictionary:
	var list: Array = []
	for s in ships:
		list.append(s.to_dict())
	return {"id": id, "tag": tag, "name": display_name, "zone": zone, "port": port, "ships": list, "mission": mission}
