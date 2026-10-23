class_name CityLandmarks
extends RefCounted
## The famous buildings of the cities (data/landmarks.json: city name -> list of {type, at, k, rot}) as models
## built from CityParts. `at` is where the landmark stands as a fraction of the city's radius from its middle
## (east, south), `k` how big it is against its usual size, `rot` how it is turned, in degrees. A landmark is
## drawn only where its foot is land. The usual size of each kind is in map pixels, the same scale as the
## rest of the city, and a bit larger than life, since a house is four pixels wide.

const CONFIG_PATH := "res://data/landmarks.json"
const SAND := Color(0.8, 0.72, 0.54)
const MARBLE := Color(0.9, 0.88, 0.82)
const GREY := Color(0.6, 0.58, 0.55)
const COPPER := Color(0.36, 0.55, 0.48)
const LEAD := Color(0.5, 0.52, 0.56)
const GOLD := Color(0.95, 0.78, 0.3)
const RED := Color(0.62, 0.22, 0.18)
const IRON := Color(0.38, 0.31, 0.25)
const SLATE := Color(0.32, 0.34, 0.38)

static var _data: Dictionary = {}
static var _loaded := false


static func for_city(city_name: String) -> Array:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data.get(city_name, [])


## How far the footprint of a kind reaches from its middle, in pixels, before scaling.
static func reach_of(kind: String) -> float:
	match kind:
		"parliament", "kremlin", "castle", "colosseum", "winter_palace", "monument", "cologne", "duomo":
			return 17.0
		"hagia_sophia", "st_peters", "basilica", "milan_cathedral", "acropolis", "tower_bridge", "ferris_wheel":
			return 14.0
		_:
			return 9.0


## Builds one landmark at `at` (its middle on the ground, y = -FOOT) and returns how tall it is.
static func build(st: SurfaceTool, spec: Dictionary, at: Vector3) -> float:
	var k := float(spec.get("k", 1.0))
	var basis := Basis(Vector3.UP, deg_to_rad(float(spec.get("rot", 0.0))))
	match str(spec.type):
		"clock_tower":
			return _clock_tower(st, at, basis, k, SAND, SLATE)
		"liver":
			return _liver(st, at, basis, k)
		"parliament":
			return _parliament(st, at, basis, k)
		"dome":
			return _domed_church(st, at, basis, k, LEAD, MARBLE)
		"gold_dome":
			return _domed_church(st, at, basis, k, GOLD, SAND)
		"copper_dome":
			return _domed_church(st, at, basis, k, COPPER, SAND)
		"red_dome":
			return _domed_church(st, at, basis, k, Color(0.72, 0.34, 0.24), MARBLE)
		"eiffel":
			return _eiffel(st, at, basis, k)
		"arc":
			return _arc(st, at, basis, k)
		"gate":
			return _gate(st, at, basis, k)
		"onions":
			return _onions(st, at, basis, k)
		"kremlin":
			return _kremlin(st, at, basis, k)
		"hagia_sophia":
			return _hagia_sophia(st, at, basis, k)
		"mosque":
			return _mosque(st, at, basis, k, 4)
		"blue_mosque":
			return _mosque(st, at, basis, k, 6)
		"colosseum":
			return _colosseum(st, at, basis, k)
		"st_peters":
			return _st_peters(st, at, basis, k)
		"cologne":
			return _gothic(st, at, basis, k, 30.0, GREY.darkened(0.12), true)
		"notre_dame":
			return _gothic(st, at, basis, k, 15.0, SAND.darkened(0.04), false)
		"stephansdom":
			return _stephansdom(st, at, basis, k)
		"milan_cathedral":
			return _milan(st, at, basis, k)
		"campanile":
			return _campanile(st, at, basis, k)
		"basilica":
			return _basilica(st, at, basis, k)
		"castle":
			return _castle(st, at, basis, k, false)
		"rock_castle":
			return _castle(st, at, basis, k, true)
		"tower_bridge":
			return _tower_bridge(st, at, basis, k)
		"white_tower":
			return _round_tower(st, at, basis, k, MARBLE, 11.0, Color(0.55, 0.5, 0.45))
		"round_tower":
			return _round_tower(st, at, basis, k, SAND.darkened(0.08), 16.0, SLATE)
		"acropolis":
			return _acropolis(st, at, basis, k)
		"ferris_wheel":
			return _ferris_wheel(st, at, basis, k)
		"lighthouse":
			return _lighthouse(st, at, basis, k)
		"spire_gold":
			return _spire_tower(st, at, basis, k, 26.0, GOLD, SAND)
		"spire_copper":
			return _spire_tower(st, at, basis, k, 20.0, COPPER, Color(0.66, 0.4, 0.3))
		"spire_brick":
			return _spire_tower(st, at, basis, k, 18.0, SLATE, RED.lightened(0.05))
		"town_hall":
			return _town_hall(st, at, basis, k)
		"winter_palace":
			return _wide_palace(st, at, basis, k, Color(0.52, 0.72, 0.62), 28.0)
		"palace":
			return _wide_palace(st, at, basis, k, SAND.lightened(0.05), 22.0)
		"monument":
			return _monument(st, at, basis, k)
		"column":
			return _column(st, at, basis, k)
		"duomo":
			return _duomo(st, at, basis, k)
		_:
			return 0.0


static func _clock_tower(st: SurfaceTool, at: Vector3, basis: Basis, k: float, stone: Color, roof: Color) -> float:
	var shaft := 15.0 * k
	CityParts.box(st, at, Vector3(3.4 * k, shaft + CityParts.FOOT, 3.4 * k), stone, basis)
	CityParts.box(st, at + Vector3(0, shaft, 0), Vector3(4.2 * k, 3.6 * k, 4.2 * k), stone.lightened(0.06), basis)
	CityParts.box(st, at + Vector3(0, shaft + 3.6 * k, 0), Vector3(3.6 * k, 1.0 * k, 3.6 * k), GOLD.darkened(0.2), basis)
	CityParts.cone(st, at + Vector3(0, shaft + 4.6 * k, 0), 2.5 * k, 6.5 * k, roof)
	CityParts.cone(st, at + Vector3(0, shaft + 11.1 * k, 0), 0.4 * k, 2.0 * k, GOLD)
	return shaft + 13.1 * k - CityParts.FOOT


static func _parliament(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(28.0 * k, 6.0 * k + CityParts.FOOT, 7.0 * k), SAND, basis)
	CityParts.gable(st, at + basis * Vector3(0, 6.0 * k, 0), Vector3(28.4 * k, 2.4 * k, 7.4 * k), SLATE, basis, true)
	for i in 5:
		CityParts.cone(st, at + basis * Vector3((-10.0 + 5.0 * i) * k, 8.0 * k, 0), 0.8 * k, 3.0 * k, SAND.darkened(0.1))
	var top := _clock_tower(st, at + basis * Vector3(15.5 * k, 0, 0), basis, k, SAND, SLATE)
	CityParts.box(st, at + basis * Vector3(-15.0 * k, 0, 0), Vector3(5.0 * k, 12.0 * k + CityParts.FOOT, 5.0 * k), SAND, basis)
	CityParts.box(st, at + basis * Vector3(-15.0 * k, 12.0 * k, 0), Vector3(5.4 * k, 2.0 * k, 5.4 * k), SAND.lightened(0.05), basis)
	return maxf(top, 14.0 * k)


static func _liver(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(14.0 * k, 10.0 * k + CityParts.FOOT, 8.0 * k), MARBLE.darkened(0.04), basis)
	var best := 0.0
	for side in [-1.0, 1.0]:
		var p: Vector3 = at + basis * Vector3(side * 5.0 * k, 10.0 * k, 0)
		CityParts.box(st, p, Vector3(3.6 * k, 6.0 * k, 3.6 * k), MARBLE, basis)
		CityParts.cone(st, p + Vector3(0, 6.0 * k, 0), 2.6 * k, 4.0 * k, COPPER)
		best = 10.0 * k + 10.0 * k
	return best


static func _domed_church(st: SurfaceTool, at: Vector3, basis: Basis, k: float, dome_colour: Color, stone: Color) -> float:
	CityParts.box(st, at, Vector3(10.0 * k, 6.0 * k + CityParts.FOOT, 22.0 * k), stone, basis)
	CityParts.box(st, at, Vector3(20.0 * k, 5.0 * k + CityParts.FOOT, 8.0 * k), stone.darkened(0.04), basis)
	CityParts.gable(st, at + basis * Vector3(0, 6.0 * k, 0), Vector3(10.4 * k, 2.2 * k, 22.4 * k), SLATE, basis, false)
	var drum: Vector3 = at + Vector3(0, 6.0 * k, 0)
	CityParts.cylinder(st, drum, 4.6 * k, 5.0 * k, stone.lightened(0.05))
	CityParts.dome(st, drum + Vector3(0, 5.0 * k, 0), 5.0 * k, 5.6 * k, dome_colour)
	CityParts.cylinder(st, drum + Vector3(0, 10.4 * k, 0), 1.0 * k, 2.2 * k, stone)
	CityParts.cone(st, drum + Vector3(0, 12.6 * k, 0), 0.8 * k, 2.4 * k, GOLD)
	for side in [-1.0, 1.0]:
		var tower: Vector3 = at + basis * Vector3(side * 3.2 * k, 0, 10.4 * k)
		CityParts.box(st, tower, Vector3(2.6 * k, 12.0 * k + CityParts.FOOT, 2.6 * k), stone)
		CityParts.cone(st, tower + Vector3(0, 12.0 * k, 0), 1.9 * k, 4.0 * k, dome_colour.darkened(0.1))
	return 15.0 * k


static func _eiffel(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var h := 32.0 * k
	var leg := 5.5 * k
	var corners := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	var first := h * 0.3
	var second := h * 0.62
	for c: Vector3 in corners:
		var foot: Vector3 = at + basis * (c * leg)
		var mid1: Vector3 = at + basis * (c * leg * 0.42) + Vector3(0, first, 0)
		var mid2: Vector3 = at + basis * (c * leg * 0.2) + Vector3(0, second, 0)
		CityParts.beam(st, foot, mid1, 1.1 * k, IRON)
		CityParts.beam(st, mid1, mid2, 0.9 * k, IRON)
		CityParts.beam(st, mid2, at + Vector3(0, h * 0.86, 0), 0.7 * k, IRON)
	for i in 4:
		CityParts.beam(st, at + basis * (corners[i] * leg * 0.9) + Vector3(0, first * 0.5, 0), at + basis * (corners[(i + 1) % 4] * leg * 0.9) + Vector3(0, first * 0.5, 0), 0.7 * k, IRON.lightened(0.05))
	CityParts.box(st, at + Vector3(0, first, 0), Vector3(5.0 * k, 0.8 * k, 5.0 * k), IRON.lightened(0.1), basis)
	CityParts.box(st, at + Vector3(0, second, 0), Vector3(2.6 * k, 0.8 * k, 2.6 * k), IRON.lightened(0.1), basis)
	CityParts.box(st, at + Vector3(0, h * 0.84, 0), Vector3(1.4 * k, 1.8 * k, 1.4 * k), IRON.lightened(0.05), basis)
	CityParts.spire(st, at + Vector3(0, h * 0.86, 0), 0.5 * k, h * 0.2, IRON)
	return h * 1.06


static func _arc(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	for side in [-1.0, 1.0]:
		CityParts.box(st, at + basis * Vector3(side * 4.2 * k, 0, 0), Vector3(4.2 * k, 11.0 * k + CityParts.FOOT, 5.5 * k), MARBLE.darkened(0.03), basis)
	CityParts.box(st, at + basis * Vector3(0, 8.0 * k, 0), Vector3(12.6 * k, 4.4 * k, 5.5 * k), MARBLE, basis)
	CityParts.box(st, at + basis * Vector3(0, 12.4 * k, 0), Vector3(12.8 * k, 1.6 * k, 5.7 * k), MARBLE.lightened(0.04), basis)
	return 14.0 * k


static func _gate(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	for i in 6:
		CityParts.cylinder(st, at + basis * Vector3((-6.0 + 2.4 * i) * k, 0, 0), 0.8 * k, 8.0 * k + CityParts.FOOT, MARBLE.darkened(0.04))
	CityParts.box(st, at + basis * Vector3(0, 8.0 * k, 0), Vector3(15.4 * k, 2.2 * k, 3.6 * k), SAND.lightened(0.06), basis)
	CityParts.box(st, at + basis * Vector3(0, 10.2 * k, 0), Vector3(15.8 * k, 1.2 * k, 3.8 * k), SAND, basis)
	CityParts.box(st, at + basis * Vector3(0, 11.4 * k, 0), Vector3(4.0 * k, 1.4 * k, 2.6 * k), COPPER, basis)
	for i in 4:
		CityParts.box(st, at + basis * Vector3((-3.0 + 2.0 * i) * k, 11.4 * k, 0), Vector3(1.0 * k, 2.2 * k, 1.8 * k), COPPER.lightened(0.05), basis)
	return 13.6 * k


static func _onions(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(15.0 * k, 5.0 * k + CityParts.FOOT, 12.0 * k), RED.lightened(0.1), basis)
	CityParts.cylinder(st, at + Vector3(0, 5.0 * k, 0), 2.4 * k, 9.0 * k, RED.lightened(0.15))
	CityParts.spire(st, at + Vector3(0, 14.0 * k, 0), 2.6 * k, 8.0 * k, Color(0.3, 0.55, 0.42))
	CityParts.cone(st, at + Vector3(0, 22.0 * k, 0), 0.5 * k, 2.0 * k, GOLD)
	var colours := [Color(0.3, 0.6, 0.4), GOLD, Color(0.25, 0.4, 0.7), Color(0.75, 0.3, 0.25), Color(0.3, 0.6, 0.4), GOLD]
	for i in 6:
		var a := TAU * i / 6.0
		var p: Vector3 = at + basis * Vector3(cos(a) * 5.4 * k, 5.0 * k, sin(a) * 4.6 * k)
		CityParts.cylinder(st, p, 1.5 * k, 3.2 * k, RED.lightened(0.18))
		CityParts.onion(st, p + Vector3(0, 3.2 * k, 0), 2.0 * k, 5.4 * k, colours[i])
	return 24.0 * k


static func _kremlin(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var w := 18.0 * k
	var d := 12.0 * k
	CityParts.box(st, at + basis * Vector3(0, 0, -d), Vector3(2.0 * w, 5.0 * k + CityParts.FOOT, 1.2 * k), RED, basis)
	CityParts.box(st, at + basis * Vector3(0, 0, d), Vector3(2.0 * w, 5.0 * k + CityParts.FOOT, 1.2 * k), RED, basis)
	CityParts.box(st, at + basis * Vector3(-w, 0, 0), Vector3(1.2 * k, 5.0 * k + CityParts.FOOT, 2.0 * d), RED, basis)
	CityParts.box(st, at + basis * Vector3(w, 0, 0), Vector3(1.2 * k, 5.0 * k + CityParts.FOOT, 2.0 * d), RED, basis)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p: Vector3 = at + basis * Vector3(cx * w, 0, cz * d)
			CityParts.box(st, p, Vector3(3.0 * k, 9.0 * k + CityParts.FOOT, 3.0 * k), RED.lightened(0.05), basis)
			CityParts.cone(st, p + Vector3(0, 9.0 * k, 0), 2.4 * k, 4.5 * k, Color(0.3, 0.5, 0.4))
	var main: Vector3 = at + basis * Vector3(0, 0, d)
	CityParts.box(st, main, Vector3(3.6 * k, 12.0 * k + CityParts.FOOT, 3.6 * k), RED.lightened(0.08), basis)
	CityParts.cone(st, main + Vector3(0, 12.0 * k, 0), 2.8 * k, 8.0 * k, Color(0.3, 0.5, 0.4))
	CityParts.cone(st, main + Vector3(0, 20.0 * k, 0), 0.5 * k, 2.0 * k, Color(0.85, 0.2, 0.2))
	for i in 3:
		var p: Vector3 = at + basis * Vector3((-6.0 + 6.0 * i) * k, 0, -2.0 * k)
		CityParts.box(st, p, Vector3(5.0 * k, 5.0 * k + CityParts.FOOT, 5.0 * k), MARBLE, basis)
		CityParts.cylinder(st, p + Vector3(0, 5.0 * k, 0), 1.4 * k, 2.4 * k, MARBLE)
		CityParts.onion(st, p + Vector3(0, 7.4 * k, 0), 1.8 * k, 4.8 * k, GOLD)
	return 22.0 * k


static func _hagia_sophia(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(17.0 * k, 8.0 * k + CityParts.FOOT, 15.0 * k), Color(0.78, 0.5, 0.4), basis)
	CityParts.cylinder(st, at + Vector3(0, 8.0 * k, 0), 6.2 * k, 2.0 * k, SAND)
	CityParts.dome(st, at + Vector3(0, 10.0 * k, 0), 6.4 * k, 5.2 * k, LEAD)
	for side in [-1.0, 1.0]:
		CityParts.dome(st, at + basis * Vector3(side * 8.0 * k, 8.0 * k, 0), 4.2 * k, 3.4 * k, LEAD.darkened(0.05))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p: Vector3 = at + basis * Vector3(cx * 10.6 * k, 0, cz * 9.4 * k)
			CityParts.cylinder(st, p, 0.9 * k, 21.0 * k + CityParts.FOOT, MARBLE)
			CityParts.cylinder(st, p + Vector3(0, 17.0 * k, 0), 1.3 * k, 0.8 * k, MARBLE.darkened(0.1))
			CityParts.cone(st, p + Vector3(0, 21.0 * k, 0), 1.0 * k, 4.0 * k, LEAD.darkened(0.15))
	return 25.0 * k


static func _mosque(st: SurfaceTool, at: Vector3, basis: Basis, k: float, minarets: int) -> float:
	CityParts.box(st, at, Vector3(14.0 * k, 6.0 * k + CityParts.FOOT, 14.0 * k), MARBLE.darkened(0.05), basis)
	CityParts.dome(st, at + Vector3(0, 6.0 * k, 0), 5.6 * k, 5.0 * k, LEAD)
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * i
		CityParts.dome(st, at + basis * Vector3(cos(a) * 5.6 * k, 6.0 * k, sin(a) * 5.6 * k), 2.6 * k, 2.4 * k, LEAD.darkened(0.06))
	for i in minarets:
		var corner := i % 4
		var a := PI * 0.25 + PI * 0.5 * corner
		var r := 10.0 * k if i < 4 else 6.4 * k
		var p: Vector3 = at + basis * Vector3(cos(a) * r, 0, sin(a) * r)
		CityParts.cylinder(st, p, 0.8 * k, 17.0 * k + CityParts.FOOT, MARBLE)
		CityParts.cylinder(st, p + Vector3(0, 12.0 * k, 0), 1.2 * k, 0.8 * k, MARBLE.darkened(0.08))
		CityParts.cone(st, p + Vector3(0, 17.0 * k, 0), 0.9 * k, 4.0 * k, LEAD.darkened(0.15))
	return 21.0 * k


static func _colosseum(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.ring(st, at, Vector2(11.5 * k, 8.8 * k), 2.6 * k, 6.5 * k + CityParts.FOOT, Color(0.84, 0.76, 0.6), basis, 24)
	CityParts.ring(st, at + Vector3(0, 4.0 * k, 0), Vector2(11.0 * k, 8.3 * k), 1.8 * k, 3.4 * k, Color(0.8, 0.7, 0.54), basis, 24)
	return 8.0 * k


static func _st_peters(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at + basis * Vector3(0, 0, 7.0 * k), Vector3(16.0 * k, 7.0 * k + CityParts.FOOT, 8.0 * k), MARBLE.darkened(0.05), basis)
	CityParts.box(st, at, Vector3(14.0 * k, 6.0 * k + CityParts.FOOT, 14.0 * k), MARBLE.darkened(0.08), basis)
	CityParts.cylinder(st, at + Vector3(0, 6.0 * k, 0), 5.6 * k, 6.0 * k, MARBLE)
	CityParts.dome(st, at + Vector3(0, 12.0 * k, 0), 6.0 * k, 7.0 * k, Color(0.68, 0.7, 0.72))
	CityParts.cylinder(st, at + Vector3(0, 19.0 * k, 0), 1.2 * k, 2.4 * k, MARBLE)
	CityParts.cone(st, at + Vector3(0, 21.4 * k, 0), 0.9 * k, 2.4 * k, GOLD)
	for side: float in [-1.0, 1.0]:
		for i in 8:
			var a := PI * 0.5 + side * (PI * 0.12 + PI * 0.32 * i / 7.0)
			CityParts.cylinder(st, at + basis * Vector3(cos(a) * 17.0 * k, 0, 12.0 * k + sin(a) * 9.0 * k), 0.5 * k, 4.0 * k + CityParts.FOOT, MARBLE)
	return 24.0 * k


static func _gothic(st: SurfaceTool, at: Vector3, basis: Basis, k: float, tower_h: float, stone: Color, openwork: bool) -> float:
	CityParts.box(st, at, Vector3(8.0 * k, 9.0 * k + CityParts.FOOT, 24.0 * k), stone, basis)
	CityParts.gable(st, at + basis * Vector3(0, 9.0 * k, 0), Vector3(8.6 * k, 4.0 * k, 24.4 * k), SLATE, basis, false)
	CityParts.box(st, at, Vector3(18.0 * k, 8.0 * k + CityParts.FOOT, 6.0 * k), stone.darkened(0.03), basis)
	var best := 0.0
	for side in [-1.0, 1.0]:
		var p: Vector3 = at + basis * Vector3(side * 2.9 * k, 0, 12.0 * k)
		var base := tower_h * 0.62 * k
		CityParts.box(st, p, Vector3(4.4 * k, base + CityParts.FOOT, 4.4 * k), stone.darkened(0.04), basis)
		if openwork:
			CityParts.box(st, p + Vector3(0, base, 0), Vector3(3.4 * k, tower_h * 0.18 * k, 3.4 * k), stone, basis)
			CityParts.spire(st, p + Vector3(0, base + tower_h * 0.18 * k, 0), 2.2 * k, tower_h * 0.5 * k, stone.lightened(0.05))
			best = base + tower_h * 0.68 * k
		else:
			CityParts.box(st, p + Vector3(0, base, 0), Vector3(4.6 * k, 1.2 * k, 4.6 * k), stone.lightened(0.05), basis)
			best = base + 1.2 * k
	if not openwork:
		CityParts.spire(st, at + Vector3(0, 12.0 * k, 0), 1.6 * k, 12.0 * k, COPPER)
		best = maxf(best, 22.0 * k)
	return best


static func _stephansdom(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(9.0 * k, 8.0 * k + CityParts.FOOT, 24.0 * k), SAND.darkened(0.1), basis)
	CityParts.gable(st, at + basis * Vector3(0, 8.0 * k, 0), Vector3(9.6 * k, 7.0 * k, 24.4 * k), Color(0.7, 0.45, 0.2), basis, false)
	var tower: Vector3 = at + basis * Vector3(4.2 * k, 0, -9.0 * k)
	CityParts.box(st, tower, Vector3(4.4 * k, 18.0 * k + CityParts.FOOT, 4.4 * k), SAND.darkened(0.1), basis)
	CityParts.spire(st, tower + Vector3(0, 18.0 * k, 0), 2.4 * k, 20.0 * k, SAND.darkened(0.12))
	CityParts.box(st, at + basis * Vector3(-4.0 * k, 0, -9.0 * k), Vector3(4.0 * k, 12.0 * k + CityParts.FOOT, 4.0 * k), SAND.darkened(0.1), basis)
	return 38.0 * k


static func _milan(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(16.0 * k, 8.0 * k + CityParts.FOOT, 26.0 * k), MARBLE, basis)
	CityParts.gable(st, at + basis * Vector3(0, 8.0 * k, 0), Vector3(16.4 * k, 3.5 * k, 26.4 * k), MARBLE.darkened(0.06), basis, false)
	for i in 9:
		for side in [-1.0, 1.0]:
			CityParts.spire(st, at + basis * Vector3(side * 7.6 * k, 8.0 * k, (-11.0 + 2.75 * i) * k), 0.7 * k, 6.0 * k, MARBLE)
	CityParts.spire(st, at + Vector3(0, 11.0 * k, 0), 1.8 * k, 18.0 * k, MARBLE.lightened(0.04))
	CityParts.cone(st, at + Vector3(0, 29.0 * k, 0), 0.5 * k, 2.0 * k, GOLD)
	return 31.0 * k


static func _duomo(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(10.0 * k, 8.0 * k + CityParts.FOOT, 22.0 * k), MARBLE.darkened(0.04), basis)
	CityParts.box(st, at + basis * Vector3(0, 0, -2.0 * k), Vector3(20.0 * k, 7.0 * k + CityParts.FOOT, 7.0 * k), MARBLE.darkened(0.06), basis)
	CityParts.cylinder(st, at + Vector3(0, 8.0 * k, 0), 5.0 * k, 3.0 * k, MARBLE)
	CityParts.dome(st, at + Vector3(0, 11.0 * k, 0), 5.2 * k, 7.0 * k, Color(0.78, 0.36, 0.26))
	CityParts.cylinder(st, at + Vector3(0, 17.4 * k, 0), 1.0 * k, 3.0 * k, MARBLE)
	CityParts.cone(st, at + Vector3(0, 20.4 * k, 0), 0.9 * k, 2.4 * k, GOLD)
	var bell: Vector3 = at + basis * Vector3(7.0 * k, 0, 11.0 * k)
	CityParts.box(st, bell, Vector3(3.4 * k, 18.0 * k + CityParts.FOOT, 3.4 * k), Color(0.9, 0.82, 0.78), basis)
	CityParts.box(st, bell + Vector3(0, 18.0 * k, 0), Vector3(3.8 * k, 2.2 * k, 3.8 * k), Color(0.9, 0.82, 0.78), basis)
	return 23.0 * k


static func _campanile(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var tower: Vector3 = at + basis * Vector3(-8.0 * k, 0, 0)
	CityParts.box(st, tower, Vector3(3.6 * k, 20.0 * k + CityParts.FOOT, 3.6 * k), Color(0.66, 0.34, 0.26), basis)
	CityParts.box(st, tower + Vector3(0, 20.0 * k, 0), Vector3(3.2 * k, 3.0 * k, 3.2 * k), MARBLE, basis)
	CityParts.cone(st, tower + Vector3(0, 23.0 * k, 0), 2.4 * k, 6.0 * k, Color(0.4, 0.55, 0.48))
	CityParts.cone(st, tower + Vector3(0, 29.0 * k, 0), 0.4 * k, 2.0 * k, GOLD)
	CityParts.box(st, at + basis * Vector3(3.0 * k, 0, 0), Vector3(16.0 * k, 6.0 * k + CityParts.FOOT, 9.0 * k), SAND, basis)
	for i in 5:
		CityParts.dome(st, at + basis * Vector3((-1.5 + 2.0 * i) * k + 3.0 * k, 6.0 * k, (i % 2 - 0.5) * 3.0 * k), 2.2 * k, 3.0 * k, LEAD.lightened(0.1))
	return 31.0 * k


static func _basilica(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.frustum(st, at, Vector2(10.0 * k, 8.0 * k), Vector2(8.0 * k, 6.0 * k), 6.0 * k + CityParts.FOOT, GREY.lightened(0.1), basis)
	CityParts.box(st, at + Vector3(0, 6.0 * k, 0), Vector3(9.0 * k, 6.0 * k, 7.0 * k), MARBLE, basis)
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * i
		CityParts.cylinder(st, at + basis * Vector3(cos(a) * 5.0 * k, 6.0 * k, sin(a) * 4.0 * k), 1.1 * k, 8.0 * k, MARBLE)
		CityParts.cone(st, at + basis * Vector3(cos(a) * 5.0 * k, 14.0 * k, sin(a) * 4.0 * k), 1.3 * k, 3.0 * k, GOLD.darkened(0.1))
	CityParts.dome(st, at + Vector3(0, 12.0 * k, 0), 3.2 * k, 3.6 * k, MARBLE.darkened(0.04))
	CityParts.cone(st, at + Vector3(0, 15.6 * k, 0), 0.8 * k, 3.0 * k, GOLD)
	return 19.0 * k


static func _castle(st: SurfaceTool, at: Vector3, basis: Basis, k: float, on_rock: bool) -> float:
	var lift := 0.0
	var stone := GREY.lightened(0.15)
	if on_rock:
		CityParts.frustum(st, at, Vector2(16.0 * k, 9.0 * k), Vector2(10.0 * k, 6.0 * k), 8.0 * k + CityParts.FOOT, GREY.darkened(0.25), basis)
		lift = 8.0 * k
	var w := 9.0 * k
	var d := 6.0 * k
	var base := at + Vector3(0, lift, 0)
	CityParts.box(st, base + basis * Vector3(0, 0, -d), Vector3(2.0 * w, 5.0 * k + (0.0 if on_rock else CityParts.FOOT), 1.2 * k), stone, basis)
	CityParts.box(st, base + basis * Vector3(0, 0, d), Vector3(2.0 * w, 5.0 * k + (0.0 if on_rock else CityParts.FOOT), 1.2 * k), stone, basis)
	CityParts.box(st, base + basis * Vector3(-w, 0, 0), Vector3(1.2 * k, 5.0 * k + (0.0 if on_rock else CityParts.FOOT), 2.0 * d), stone, basis)
	CityParts.box(st, base + basis * Vector3(w, 0, 0), Vector3(1.2 * k, 5.0 * k + (0.0 if on_rock else CityParts.FOOT), 2.0 * d), stone, basis)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p: Vector3 = base + basis * Vector3(cx * w, 0, cz * d)
			CityParts.cylinder(st, p, 1.8 * k, 8.0 * k + (0.0 if on_rock else CityParts.FOOT), stone.darkened(0.04))
			CityParts.cone(st, p + Vector3(0, 8.0 * k, 0), 2.1 * k, 3.5 * k, Color(0.36, 0.4, 0.44))
	CityParts.box(st, base, Vector3(6.0 * k, 11.0 * k + (0.0 if on_rock else CityParts.FOOT), 5.0 * k), stone.lightened(0.05), basis)
	CityParts.gable(st, base + Vector3(0, 11.0 * k, 0), Vector3(6.4 * k, 3.0 * k, 5.4 * k), Color(0.45, 0.3, 0.26), basis, true)
	return lift + 14.0 * k


static func _tower_bridge(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var gap := 7.5 * k
	for side in [-1.0, 1.0]:
		var p: Vector3 = at + basis * Vector3(side * gap, 0, 0)
		CityParts.box(st, p, Vector3(4.2 * k, 13.0 * k + CityParts.FOOT, 4.2 * k), Color(0.7, 0.68, 0.62), basis)
		for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			CityParts.cone(st, p + basis * Vector3(corner.x * 1.6 * k, 13.0 * k, corner.y * 1.6 * k), 0.9 * k, 3.2 * k, Color(0.32, 0.4, 0.5))
	CityParts.box(st, at + basis * Vector3(0, 3.0 * k, 0), Vector3(2.0 * gap, 1.4 * k, 3.4 * k), Color(0.3, 0.45, 0.62), basis)
	CityParts.box(st, at + basis * Vector3(0, 11.0 * k, 0), Vector3(2.0 * gap, 1.0 * k, 2.2 * k), Color(0.3, 0.45, 0.62), basis)
	for side in [-1.0, 1.0]:
		CityParts.box(st, at + basis * Vector3(side * (gap + 5.5 * k), 0, 0), Vector3(7.0 * k, 3.0 * k + CityParts.FOOT, 3.4 * k), Color(0.3, 0.45, 0.62), basis)
	return 17.0 * k


static func _round_tower(st: SurfaceTool, at: Vector3, basis: Basis, k: float, colour: Color, height: float, roof: Color) -> float:
	CityParts.cylinder(st, at, 3.0 * k, height * k + CityParts.FOOT, colour)
	CityParts.cylinder(st, at + Vector3(0, height * k, 0), 3.4 * k, 1.0 * k, colour.darkened(0.1))
	CityParts.cone(st, at + Vector3(0, (height + 1.0) * k, 0), 3.0 * k, 3.5 * k, roof)
	return (height + 4.5) * k


static func _acropolis(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.frustum(st, at, Vector2(15.0 * k, 9.0 * k), Vector2(11.0 * k, 6.0 * k), 7.0 * k + CityParts.FOOT, Color(0.62, 0.56, 0.46), basis)
	var top := at + Vector3(0, 7.0 * k, 0)
	CityParts.box(st, top, Vector3(16.0 * k, 0.8 * k, 7.0 * k), MARBLE.darkened(0.04), basis)
	for row in [-1.0, 1.0]:
		for i in 8:
			CityParts.cylinder(st, top + basis * Vector3((-7.0 + 2.0 * i) * k, 0.8 * k, row * 2.8 * k), 0.55 * k, 4.6 * k, MARBLE)
	CityParts.box(st, top + basis * Vector3(0, 5.4 * k, 0), Vector3(16.4 * k, 1.0 * k, 7.4 * k), MARBLE, basis)
	CityParts.gable(st, top + basis * Vector3(0, 6.4 * k, 0), Vector3(16.6 * k, 1.8 * k, 7.6 * k), MARBLE.darkened(0.08), basis, true)
	return 7.0 * k + 8.2 * k


static func _ferris_wheel(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var r := 10.0 * k
	var hub := at + Vector3(0, r + 2.0 * k, 0)
	var steps := 20
	var prev := Vector3.ZERO
	for i in steps + 1:
		var a := TAU * i / steps
		var rim := hub + basis * Vector3(cos(a) * r, sin(a) * r, 0)
		if i > 0:
			CityParts.beam(st, prev, rim, 0.55 * k, IRON.lightened(0.1))
		if i < steps and i % 2 == 0:
			CityParts.beam(st, hub, rim, 0.3 * k, IRON.lightened(0.2))
			CityParts.box(st, rim - Vector3(0, 0.8 * k, 0), Vector3(1.2 * k, 1.2 * k, 1.2 * k), RED, basis)
		prev = rim
	for side in [-1.0, 1.0]:
		CityParts.beam(st, at + basis * Vector3(side * 4.5 * k, 0, 0), hub, 0.9 * k, IRON)
	return 2.0 * k + 2.0 * r


static func _lighthouse(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(5.0 * k, 10.0 * k + CityParts.FOOT, 5.0 * k), MARBLE.darkened(0.06), basis)
	CityParts.box(st, at + Vector3(0, 10.0 * k, 0), Vector3(3.6 * k, 9.0 * k, 3.6 * k), MARBLE, basis)
	CityParts.cylinder(st, at + Vector3(0, 19.0 * k, 0), 2.0 * k, 2.4 * k, Color(0.3, 0.34, 0.4))
	CityParts.cone(st, at + Vector3(0, 21.4 * k, 0), 1.9 * k, 2.4 * k, GOLD.darkened(0.1))
	return 24.0 * k


static func _spire_tower(st: SurfaceTool, at: Vector3, basis: Basis, k: float, height: float, spire_colour: Color, stone: Color) -> float:
	var shaft := height * 0.55 * k
	CityParts.box(st, at, Vector3(4.4 * k, shaft + CityParts.FOOT, 4.4 * k), stone, basis)
	CityParts.box(st, at + Vector3(0, shaft, 0), Vector3(3.6 * k, 3.0 * k, 3.6 * k), stone.lightened(0.05), basis)
	CityParts.spire(st, at + Vector3(0, shaft + 3.0 * k, 0), 2.0 * k, height * 0.7 * k, spire_colour)
	return shaft + 3.0 * k + height * 0.7 * k


static func _town_hall(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(18.0 * k, 7.0 * k + CityParts.FOOT, 8.0 * k), Color(0.74, 0.6, 0.5), basis)
	CityParts.gable(st, at + basis * Vector3(0, 7.0 * k, 0), Vector3(18.4 * k, 3.0 * k, 8.4 * k), SLATE, basis, true)
	var top := _clock_tower(st, at + basis * Vector3(-3.0 * k, 0, 0), basis, k * 0.9, Color(0.74, 0.6, 0.5), COPPER)
	return top


static func _wide_palace(st: SurfaceTool, at: Vector3, basis: Basis, k: float, wall: Color, length: float) -> float:
	CityParts.box(st, at, Vector3(length * k, 8.0 * k + CityParts.FOOT, 8.0 * k), wall, basis)
	CityParts.box(st, at + basis * Vector3(0, 8.0 * k, 0), Vector3(length * k + 0.8 * k, 1.0 * k, 8.8 * k), MARBLE, basis)
	for i in 7:
		CityParts.box(st, at + basis * Vector3((-0.42 * length + 0.14 * length * i) * k, 4.0 * k, 4.0 * k), Vector3(0.7 * k, 4.0 * k, 0.7 * k), MARBLE, basis)
	CityParts.box(st, at + basis * Vector3(0, 0, 0), Vector3(8.0 * k, 11.0 * k + CityParts.FOOT, 9.0 * k), wall.lightened(0.06), basis)
	CityParts.gable(st, at + basis * Vector3(0, 11.0 * k, 0), Vector3(8.4 * k, 3.0 * k, 9.4 * k), Color(0.3, 0.45, 0.42), basis, false)
	return 14.0 * k


static func _monument(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.frustum(st, at, Vector2(12.0 * k, 5.0 * k), Vector2(10.0 * k, 4.0 * k), 3.0 * k + CityParts.FOOT, MARBLE.darkened(0.04), basis)
	CityParts.box(st, at + Vector3(0, 3.0 * k, 0), Vector3(20.0 * k, 5.0 * k, 5.0 * k), MARBLE, basis)
	for i in 14:
		CityParts.cylinder(st, at + basis * Vector3((-8.0 + 1.23 * i) * k, 8.0 * k, 2.2 * k), 0.45 * k, 5.0 * k, MARBLE)
	CityParts.box(st, at + Vector3(0, 13.0 * k, 0), Vector3(20.6 * k, 1.2 * k, 5.6 * k), MARBLE.lightened(0.04), basis)
	for side in [-1.0, 1.0]:
		CityParts.box(st, at + basis * Vector3(side * 9.0 * k, 14.2 * k, 0), Vector3(2.0 * k, 2.4 * k, 2.0 * k), GOLD.darkened(0.12), basis)
	return 17.0 * k


static func _column(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	CityParts.box(st, at, Vector3(4.0 * k, 3.0 * k + CityParts.FOOT, 4.0 * k), MARBLE.darkened(0.05), basis)
	CityParts.cylinder(st, at + Vector3(0, 3.0 * k, 0), 1.1 * k, 18.0 * k, MARBLE)
	CityParts.box(st, at + Vector3(0, 21.0 * k, 0), Vector3(2.4 * k, 1.2 * k, 2.4 * k), GOLD.darkened(0.15), basis)
	CityParts.cone(st, at + Vector3(0, 22.2 * k, 0), 0.8 * k, 2.4 * k, GOLD)
	return 24.6 * k
