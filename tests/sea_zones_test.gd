extends SceneTree
## Headless test for the sea zone layer: every sea pixel in a zone (bar the Arctic and the
## Caspian), a connected zone graph, ports opening on the right water, and zone picking.
## Run: godot --headless --path . -s res://tests/sea_zones_test.gd

var _failures := 0
var map: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _zone_id(zone_name: String) -> int:
	for z in map.sea_zones:
		if z.get("name", "") == zone_name:
			return z.id
	return 0


func _province(province_name: String) -> int:
	for p in map.provinces:
		if p.get("name", "") == province_name:
			return p.id
	return 0


func _initialize() -> void:
	await process_frame
	map = root.get_node("MapData")
	var zones: int = map.sea_zones.size() - 1
	_check(zones >= 35, "%d sea zones loaded" % zones)
	_check(map.sea_zones_image.get_width() * map.ZONE_SCALE >= map.map_size.x, "the zone image covers the map")

	# Every zone has water, a centre on water in that zone, and a neighbour.
	var bad := 0
	for id in range(1, zones + 1):
		var z: Dictionary = map.sea_zones[id]
		var c: Vector2i = Vector2i(z.center)
		if map.province_at_pixel(c) != map.SEA or map.sea_zone_at_pixel(c) != id or map.sea_adjacency[id].is_empty():
			bad += 1
			printerr("zone ", id, " ", z.name, " is malformed")
	_check(bad == 0, "every zone's centre is water inside that zone, and every zone has a neighbour")
	# A fleet in port is drawn on the water off its harbour, not on the land.
	var FL = load("res://scripts/map/fleet_layer.gd")
	var on_land: Array = []
	var far := 0
	for port: int in map.port_zones:
		var spot: Vector2 = FL.harbour_spot(port)
		if map.province_at_pixel(Vector2i(spot.floor())) != map.SEA:
			on_land.append(map.provinces[port].name)
		elif spot.distance_to(map.provinces[port].center) > 400.0:
			far += 1
	_check(on_land.is_empty(), "every port's ships lie on the water (%d ports; on land: %s)" % [map.port_zones.size(), ", ".join(on_land)])
	_check(far == 0, "and near the port (%d far off)" % far)

	# The zone graph is connected and symmetric.
	var seen := {1: true}
	var todo := [1]
	var symmetric := true
	while not todo.is_empty():
		var z: int = todo.pop_back()
		for n in map.sea_adjacency[z]:
			symmetric = symmetric and map.sea_adjacency[n].has(z)
			if not seen.has(n):
				seen[n] = true
				todo.append(n)
	_check(seen.size() == zones, "the zone graph is connected")
	_check(symmetric, "zone adjacency is symmetric")

	# Known neighbours.
	var channel: int = _zone_id("Eastern Channel")
	_check(map.sea_adjacency[channel].has(_zone_id("Southern North Sea")), "the Eastern Channel opens on the Southern North Sea")
	_check(map.sea_adjacency[channel].has(_zone_id("Western Channel")), "the Eastern and Western Channel touch")
	_check(not map.sea_adjacency[_zone_id("Western Black Sea")].has(_zone_id("North Atlantic")), "the Black Sea is nowhere near the North Atlantic")
	_check(map.sea_adjacency[_zone_id("Sea of Marmara")].has(_zone_id("Aegean Sea")), "Marmara opens on the Aegean")
	_check(map.sea_adjacency[_zone_id("Danish Straits")].has(_zone_id("Southern Baltic")), "the Danish Straits lead into the Baltic")

	# Ports.
	var kent: int = _province("Kent")
	_check(kent > 0 and map.zones_of_port(kent).has(channel) or map.zones_of_port(kent).has(_zone_id("Southern North Sea")),
			"Kent has a port on the Channel or the North Sea")
	var crimea: int = _province("Sevastopol") if _province("Sevastopol") > 0 else _province("Krym")
	if crimea > 0:
		var black := [_zone_id("Western Black Sea"), _zone_id("Northwestern Black Sea"), _zone_id("Eastern Black Sea"), _zone_id("Sea of Azov")]
		var ok := false
		for z in map.zones_of_port(crimea):
			ok = ok or black.has(z)
		_check(ok, "the Crimea opens on the Black Sea")
	var inland: int = _province("Berne")
	if inland > 0:
		_check(map.zones_of_port(inland).is_empty(), "a landlocked province has no port zone")
	var wrong := 0
	for pid in map.port_zones:
		if not map.provinces[pid].coastal:
			wrong += 1
	_check(wrong == 0, "every port is a coastal province")
	var unported := 0
	for p in map.provinces:
		if p.get("coastal", false) and not map.port_zones.has(p.id):
			unported += 1
	_check(unported <= 12, "only the Arctic and Caspian coast lacks a port zone (%d provinces)" % unported)

	# Picking: land gives no zone, open water does.
	_check(map.sea_zone_at_pixel(Vector2i(map.sea_zones[_zone_id("Central North Sea")].center)) == _zone_id("Central North Sea"), "the middle of the North Sea is in its zone")
	_check(map.sea_zone_at_pixel(Vector2i(3000, 2500)) == 0, "inland pixels belong to no zone")
	_check(map.sea_zone_at_pixel(Vector2i(-5, -5)) == 0, "off the map belongs to no zone")

	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)
