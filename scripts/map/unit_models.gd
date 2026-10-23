class_name UnitModels
extends RefCounted
## Models of the armies and fleets of the 3D map, as small low-poly figures built like the cities
## (CityParts, vertex colours): a formation of soldiers, horsemen and guns in the nation's uniform colour
## for an army, a line of ships for a fleet. One model is a mesh in model units (a soldier is 1.7 tall, the
## front of a formation 20 or so wide), x the way it faces; the map scales it. Meshes are cached by what
## they show (nation colour, how many of each kind, class of ship), so ten thousand men or ten
## thousand and one are the same model: strength shows in size classes, not in every man.

const SOLDIER := 1.7
const MAX_UNITS := 12          # divisions drawn in one formation
const MAX_SHIPS := 8
const DEEP := 9                # ranks or columns of a block never go beyond this

static var _cache := {}


## The most of each kind a formation shows, scaled so that all together are at most MAX_UNITS and each kind
## there is at all is at least one.
static func army_counts(comp: Dictionary, men: float) -> Dictionary:
	var counts := {}
	var total := 0
	for type: String in ["infantry", "cavalry", "artillery"]:
		var n := int(comp.get(type, 0))
		if n > 0:
			counts[type] = n
			total += n
	if total == 0:
		counts["infantry"] = clampi(roundi(men / 12000.0), 1, MAX_UNITS)
		return counts
	if total > MAX_UNITS:
		var f := float(MAX_UNITS) / total
		for type: String in counts:
			counts[type] = maxi(1, roundi(counts[type] * f))
	return counts


## The mesh of an army of this make-up in this nation's colour, cached.
static func army_mesh(counts: Dictionary, colour: Color) -> ArrayMesh:
	var key := "a%s|%d|%d|%d" % [colour.to_html(false), counts.get("infantry", 0), counts.get("cavalry", 0), counts.get("artillery", 0)]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uniform := colour.lerp(Color(0.5, 0.48, 0.4), 0.55).darkened(0.1)
	var z := 0.0
	var order := ["infantry", "artillery", "cavalry"]
	var widths := {}
	var total := 0.0
	for type: String in order:
		var n: int = counts.get(type, 0)
		if n > 0:
			widths[type] = _block_width(type, n)
			total += float(widths[type]) + 3.0
	z = -total * 0.5
	for type: String in order:
		if not widths.has(type):
			continue
		var w: float = widths[type]
		var centre := Vector3(0, 0, z + w * 0.5)
		match type:
			"infantry": _infantry(st, centre, counts[type], uniform, colour)
			"artillery": _artillery(st, centre, counts[type], uniform)
			"cavalry": _cavalry(st, centre, counts[type], uniform, colour)
		z += w + 3.0
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _block_width(type: String, n: int) -> float:
	match type:
		"infantry": return float(mini(DEEP, 2 + n)) * 1.5
		"artillery": return float(n) * 6.0
		_: return float(n) * 3.4
	return 6.0


## A box on `at` (the middle of its foot), shaded by face but not like a building.
static func block(st: SurfaceTool, at: Vector3, size: Vector3, colour: Color, basis := Basis.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return at + basis * Vector3(x, y, z)
	var a: Vector3 = c.call(-hx, 0, -hz)
	var b: Vector3 = c.call(hx, 0, -hz)
	var d: Vector3 = c.call(hx, 0, hz)
	var e: Vector3 = c.call(-hx, 0, hz)
	var a2: Vector3 = c.call(-hx, size.y, -hz)
	var b2: Vector3 = c.call(hx, size.y, -hz)
	var d2: Vector3 = c.call(hx, size.y, hz)
	var e2: Vector3 = c.call(-hx, size.y, hz)
	CityParts.quad(st, e, d, d2, e2, colour.darkened(0.06))
	CityParts.quad(st, b, a, a2, b2, colour.darkened(0.12))
	CityParts.quad(st, d, b, b2, d2, colour.darkened(0.03))
	CityParts.quad(st, a, e, e2, a2, colour.darkened(0.15))
	CityParts.quad(st, e2, d2, b2, a2, colour.lightened(0.08))


## Rows of marching soldiers: a body in uniform, a head, a rifle, a pack, and a flag bearer in the lead.
static func _infantry(st: SurfaceTool, centre: Vector3, units: int, uniform: Color, flag: Color) -> void:
	var cols := mini(DEEP, 2 + units)
	var ranks := 2 + mini(units, 4)
	var skin := Color(0.85, 0.7, 0.58)
	var helmet := uniform.darkened(0.35)
	for r in ranks:
		for c in cols:
			var p := centre + Vector3((float(r) - ranks * 0.5) * 1.5, 0, (float(c) - (cols - 1) * 0.5) * 1.5)
			block(st, p + Vector3(0, 0.0, 0), Vector3(0.55, 1.15, 0.5), uniform)
			block(st, p + Vector3(0, 1.15, 0), Vector3(0.42, 0.42, 0.42), skin)
			block(st, p + Vector3(0, 1.57, 0), Vector3(0.5, 0.18, 0.5), helmet)
			CityParts.beam(st, p + Vector3(0.25, 0.4, 0.3), p + Vector3(-0.3, 1.9, 0.3), 0.14, Color(0.25, 0.18, 0.12))
			block(st, p + Vector3(-0.35, 0.35, 0), Vector3(0.25, 0.6, 0.45), uniform.darkened(0.25))
	var lead := centre + Vector3(-ranks * 0.75 - 1.0, 0, 0)
	CityParts.beam(st, lead + Vector3(0, 0, 0), lead + Vector3(0, 4.6, 0), 0.14, Color(0.2, 0.15, 0.1))
	block(st, lead + Vector3(0, 3.5, 0), Vector3(0.06, 1.1, 1.5), flag)


## Horsemen, three to a troop: a barrel body, neck, head and four legs, the rider with a cap and lance.
static func _cavalry(st: SurfaceTool, centre: Vector3, troops: int, uniform: Color, flag: Color) -> void:
	var horse := Color(0.42, 0.28, 0.18)
	for t in troops:
		for k in 3:
			var p := centre + Vector3((float(k) - 1.0) * 2.8, 0, (float(t) - (troops - 1) * 0.5) * 3.4)
			var shade := horse.lightened(0.12 * float((t + k) % 3)).darkened(0.05 * float(k))
			block(st, p + Vector3(0, 1.05, 0), Vector3(2.2, 0.9, 0.8), shade)
			block(st, p + Vector3(1.2, 1.45, 0), Vector3(0.7, 1.0, 0.45), shade)
			block(st, p + Vector3(1.7, 2.0, 0), Vector3(0.8, 0.4, 0.4), shade.darkened(0.06))
			for lx in [-0.85, 0.85]:
				for lz in [-0.28, 0.28]:
					block(st, p + Vector3(lx, 0, lz), Vector3(0.2, 1.1, 0.2), shade.darkened(0.2))
			block(st, p + Vector3(-0.1, 1.95, 0), Vector3(0.5, 0.95, 0.45), uniform)
			block(st, p + Vector3(-0.1, 2.9, 0), Vector3(0.38, 0.38, 0.38), Color(0.85, 0.7, 0.58))
			block(st, p + Vector3(-0.1, 3.25, 0), Vector3(0.42, 0.16, 0.42), uniform.darkened(0.3))
			CityParts.beam(st, p + Vector3(-0.9, 1.6, 0.35), p + Vector3(1.9, 4.2, 0.35), 0.1, Color(0.3, 0.22, 0.14))
	var lead := centre + Vector3(2.6, 0, 0)
	block(st, lead + Vector3(0, 3.8, 0), Vector3(0.06, 0.8, 1.1), flag)


## Field guns, two to a battery: a barrel on two spoked wheels with a trail, and a crew man by each.
static func _artillery(st: SurfaceTool, centre: Vector3, batteries: int, uniform: Color) -> void:
	var metal := Color(0.26, 0.28, 0.3)
	var wood := Color(0.4, 0.3, 0.2)
	for g in batteries:
		for side in [-1.0, 1.0]:
			var p := centre + Vector3(0, 0, (float(g) - (batteries - 1) * 0.5) * 6.0 + side * 1.4)
			CityParts.beam(st, p + Vector3(-0.3, 1.2, 0), p + Vector3(2.6, 1.7, 0), 0.32, metal)
			block(st, p + Vector3(-0.1, 0.6, 0), Vector3(1.6, 0.5, 0.8), wood)
			CityParts.beam(st, p + Vector3(-0.2, 0.7, 0), p + Vector3(-3.0, 0.1, 0), 0.35, wood)
			for sz in [-0.55, 0.55]:
				CityParts.beam(st, p + Vector3(0.3, 0.15, sz), p + Vector3(0.3, 1.25, sz), 0.28, wood)
				CityParts.beam(st, p + Vector3(-0.3, 0.7, sz), p + Vector3(0.9, 0.7, sz), 0.28, wood)
			var crew := p + Vector3(-1.6, 0, side * 0.3)
			block(st, crew, Vector3(0.55, 1.15, 0.5), uniform)
			block(st, crew + Vector3(0, 1.15, 0), Vector3(0.42, 0.42, 0.42), Color(0.85, 0.7, 0.58))
			block(st, crew + Vector3(0, 1.57, 0), Vector3(0.5, 0.18, 0.5), uniform.darkened(0.35))


# ------------------------------------------------------------------ ships

## The classes of ships of a fleet to draw, as a list, at most MAX_SHIPS: the biggest first.
static func fleet_line(classes: Dictionary) -> Array:
	var out: Array = []
	for type: String in ["dreadnought", "cruiser", "transport", "destroyer", "submarine"]:
		for i in int(classes.get(type, 0)):
			out.append(type)
	if out.size() > MAX_SHIPS:
		var kinds := {}
		for t: String in out:
			kinds[t] = int(kinds.get(t, 0)) + 1
		var f := float(MAX_SHIPS) / out.size()
		out.clear()
		for type: String in ["dreadnought", "cruiser", "transport", "destroyer", "submarine"]:
			for i in maxi(1 if kinds.has(type) else 0, roundi(int(kinds.get(type, 0)) * f)):
				out.append(type)
		out.resize(mini(out.size(), MAX_SHIPS))
	if out.is_empty():
		out.append("cruiser")
	return out


static func fleet_mesh(line: Array, colour: Color) -> ArrayMesh:
	var key := "f%s|%s" % [colour.to_html(false), ",".join(PackedStringArray(line))]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := 0.0
	var total := 0.0
	for type: String in line:
		total += _ship_length(type) + 5.0
	var x := -total * 0.5
	for i in line.size():
		var type: String = line[i]
		var length := _ship_length(type)
		x += length * 0.5
		_ship(st, Vector3(x, 0, (float(i % 2) - 0.5) * 4.0), type, colour)
		x += length * 0.5 + 5.0
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _ship_length(type: String) -> float:
	match type:
		"dreadnought": return 26.0
		"cruiser": return 21.0
		"transport": return 20.0
		"destroyer": return 14.0
		"submarine": return 11.0
	return 16.0


## One ship at `at`, bow toward +x: the hull in grey (a transport is black with a red band), a pointed
## bow, a bridge, funnels, masts, and turrets by class; a submarine is a low whale with a conning tower.
static func _ship(st: SurfaceTool, at: Vector3, type: String, colour: Color) -> void:
	var length := _ship_length(type)
	var hull := Color(0.42, 0.45, 0.5)
	var deck := Color(0.55, 0.52, 0.46)
	var funnel := Color(0.3, 0.3, 0.33)
	var beam := 4.2
	var freeboard := 2.4
	match type:
		"transport":
			hull = Color(0.14, 0.15, 0.18)
			funnel = colour.darkened(0.1)
			beam = 5.0
			freeboard = 3.6
		"destroyer":
			beam = 2.2
			freeboard = 1.6
		"cruiser":
			beam = 3.4
		"submarine":
			hull = Color(0.2, 0.22, 0.25)
			beam = 2.2
			freeboard = 1.1
		"dreadnought":
			beam = 5.2
			freeboard = 3.0
	var hl := length * 0.82
	block(st, at + Vector3(-length * 0.5 + hl * 0.5, 0, 0), Vector3(hl, freeboard, beam), hull)
	var bow := at + Vector3(-length * 0.5 + hl, 0, 0)
	var hb := beam * 0.5
	CityParts.tri(st, bow + Vector3(0, freeboard, hb), bow + Vector3(0, freeboard, -hb), bow + Vector3(length * 0.18, freeboard, 0), deck)
	CityParts.quad(st, bow + Vector3(0, 0, -hb), bow + Vector3(0, freeboard, -hb), bow + Vector3(length * 0.18, freeboard, 0), bow + Vector3(length * 0.18, 0, 0), hull.darkened(0.08))
	CityParts.quad(st, bow + Vector3(length * 0.18, 0, 0), bow + Vector3(length * 0.18, freeboard, 0), bow + Vector3(0, freeboard, hb), bow + Vector3(0, 0, hb), hull.darkened(0.04))
	block(st, at + Vector3(-length * 0.5 + hl * 0.5, freeboard, 0), Vector3(hl * 0.98, 0.12, beam * 0.96), deck)
	if type == "transport":
		block(st, at + Vector3(-length * 0.5 + hl * 0.5, freeboard * 0.55, 0), Vector3(hl + 0.05, 0.5, beam + 0.05), Color(0.62, 0.2, 0.16))
	var top := freeboard + 0.12
	match type:
		"submarine":
			block(st, at + Vector3(-1.0, top, 0), Vector3(2.4, 1.6, 1.0), hull.lightened(0.05))
			CityParts.beam(st, at + Vector3(-0.5, top + 1.6, 0), at + Vector3(-0.5, top + 3.0, 0), 0.18, funnel)
		"destroyer":
			block(st, at + Vector3(2.5, top, 0), Vector3(3.0, 1.3, 1.6), Color(0.78, 0.77, 0.72))
			CityParts.cylinder(st, at + Vector3(-1.0, top, 0), 0.7, 2.4, funnel)
			CityParts.cylinder(st, at + Vector3(-3.4, top, 0), 0.7, 2.2, funnel)
			_turret(st, at + Vector3(5.5, top, 0), 0.8, 1)
			_turret(st, at + Vector3(-5.5, top, 0), 0.8, -1)
		"cruiser":
			block(st, at + Vector3(2.8, top, 0), Vector3(4.2, 2.0, 2.4), Color(0.78, 0.77, 0.72))
			for fx in [-0.5, -3.8]:
				CityParts.cylinder(st, at + Vector3(fx, top, 0), 0.95, 3.4, funnel)
			CityParts.beam(st, at + Vector3(2.8, top + 2.0, 0), at + Vector3(2.8, top + 6.0, 0), 0.22, funnel)
			_turret(st, at + Vector3(7.0, top, 0), 1.1, 1)
			_turret(st, at + Vector3(-7.5, top, 0), 1.1, -1)
			_turret(st, at + Vector3(-4.8, top, 0), 1.0, -1)
		"transport":
			block(st, at + Vector3(2.0, top, 0), Vector3(5.0, 3.0, 3.6), Color(0.85, 0.84, 0.78))
			CityParts.cylinder(st, at + Vector3(-2.6, top, 0), 1.2, 4.6, funnel)
			CityParts.beam(st, at + Vector3(6.0, top, 0), at + Vector3(6.0, top + 6.0, 0), 0.25, funnel)
			CityParts.beam(st, at + Vector3(-6.5, top, 0), at + Vector3(-6.5, top + 5.0, 0), 0.25, funnel)
		"dreadnought":
			block(st, at + Vector3(2.0, top, 0), Vector3(5.0, 3.2, 3.2), Color(0.78, 0.77, 0.72))
			for fx in [-1.6, -5.0]:
				CityParts.cylinder(st, at + Vector3(fx, top, 0), 1.2, 4.2, funnel)
			CityParts.beam(st, at + Vector3(2.0, top + 3.2, 0), at + Vector3(2.0, top + 9.0, 0), 0.3, funnel)
			CityParts.beam(st, at + Vector3(-9.0, top, 0), at + Vector3(-9.0, top + 6.5, 0), 0.25, funnel)
			_turret(st, at + Vector3(8.2, top, 0), 1.5, 1)
			_turret(st, at + Vector3(5.6, top + 0.9, 0), 1.4, 1)
			_turret(st, at + Vector3(-6.8, top + 0.9, 0), 1.4, -1)
			_turret(st, at + Vector3(-9.8, top, 0), 1.5, -1)
			for s in [-1.0, 1.0]:
				_turret(st, at + Vector3(-0.5, top, s * 2.0), 0.9, 1)
	# the nation's colour: a stripe along the deck and a pennant on a mast, the one thing a fleet and a fleet differ by
	block(st, at + Vector3(-length * 0.5 + hl * 0.5, top, 0), Vector3(hl * 0.6, 0.18, 0.7), colour)


static func _turret(st: SurfaceTool, at: Vector3, size: float, facing: int) -> void:
	block(st, at, Vector3(size * 1.5, size * 0.7, size * 1.4), Color(0.36, 0.38, 0.42))
	for z in [-0.28, 0.28]:
		CityParts.beam(st, at + Vector3(0, size * 0.4, z * size), at + Vector3(facing * size * 2.0, size * 0.5, z * size), 0.2 * size + 0.1, Color(0.2, 0.2, 0.22))
