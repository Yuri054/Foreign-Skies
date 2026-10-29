class_name UnitModels
extends RefCounted
## Models of the armies and fleets of the 3D map, as small low-poly figures built like the cities
## (CityParts, vertex colours): every unit of an army one model of its own, a soldier, a horseman or a gun, in the
## nation's uniform colour; a line of ships for a fleet. One model is a mesh in model units (a soldier is 1.7 tall),
## x the way it faces; the map scales it. Meshes are cached by what
## they show (nation colour, how many of each kind, class of ship), so ten thousand men or ten
## thousand and one are the same model: strength shows in size classes, not in every man.

const SOLDIER := 1.7
const MAX_UNITS := 9           # units (divisions) drawn in one group, each a model of its own
const MAX_SHIPS := 8
const DEEP := 9                # ranks or columns of a block never go beyond this

## Model units between the units of a group, and the height of the base they stand on.
const SLOT := 4.2
const BASE_H := 0.22

static var _cache := {}


## The colour of a nation's uniforms: mostly its own colour, a little toward field drab, and never so dark that the
## figures turn black against the ground.
static func uniform_colour(colour: Color) -> Color:
	var c := colour.lerp(Color(0.52, 0.5, 0.42), 0.25)
	if c.get_luminance() < 0.3:
		c = c.lerp(Color(0.62, 0.62, 0.6), (0.3 - c.get_luminance()) * 1.6)
	return c


## The stand a unit is on, as on a wargames table: a low slab with cut corners in the nation's colour, a lighter
## edge round it, `size` across (x along the way it faces), centred on `at`.
static func _base(st: SurfaceTool, at: Vector3, size: Vector2, colour: Color) -> void:
	var top := colour.darkened(0.15)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var cut := minf(hx, hz) * 0.35
	var ring: Array[Vector3] = [Vector3(hx - cut, 0, -hz), Vector3(hx, 0, -hz + cut), Vector3(hx, 0, hz - cut), Vector3(hx - cut, 0, hz),
			Vector3(-hx + cut, 0, hz), Vector3(-hx, 0, hz - cut), Vector3(-hx, 0, -hz + cut), Vector3(-hx + cut, 0, -hz)]
	var up := Vector3(0, BASE_H, 0)
	var centre := at + up
	for i in ring.size():
		var a: Vector3 = at + ring[i]
		var b: Vector3 = at + ring[(i + 1) % ring.size()]
		CityParts.tri(st, centre, b + up, a + up, top)
		# The edge reaches down below the foot, so a stand lifted over a slope reads as a block, not a floating plate.
		var skirt := Vector3(0, -1.5, 0)
		CityParts.quad(st, b + skirt, a + skirt, a + up, b + up, colour.lightened(0.25))


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


## The mesh of an army of this make-up in this nation's colour, cached: every unit (a division) is one
## model, a soldier, a horseman or a gun, standing in a loose group.
static func army_mesh(counts: Dictionary, colour: Color) -> ArrayMesh:
	var key := "a%s|%d|%d|%d" % [colour.to_html(false), counts.get("infantry", 0), counts.get("cavalry", 0), counts.get("artillery", 0)]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uniform := uniform_colour(colour)
	var figures: Array[String] = []
	for type: String in ["infantry", "artillery", "cavalry"]:
		for i in int(counts.get(type, 0)):
			figures.append(type)
	var cols := mini(4, maxi(1, ceili(sqrt(figures.size()))))
	var rows := ceili(float(figures.size()) / cols)
	for i in figures.size():
		var foot := Vector3(((i / cols) - (rows - 1) * 0.5) * SLOT, 0, ((i % cols) - (cols - 1) * 0.5) * SLOT)
		_base(st, foot, Vector2(3.4, 3.0) if figures[i] != "cavalry" else Vector2(3.6, 2.2), colour)
		var at := foot + Vector3(0, BASE_H, 0)
		match figures[i]:
			"infantry":
				# A division is a file of three: the leader, and two behind (the first file carries the flag).
				_soldier(st, at + Vector3(1.0, 0, 0), uniform, colour, i == 0)
				_soldier(st, at + Vector3(-0.5, 0, -0.85), uniform, colour, false)
				_soldier(st, at + Vector3(-0.5, 0, 0.85), uniform, colour, false)
			"artillery": _gun(st, at, uniform)
			"cavalry": _horseman(st, at, uniform)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


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


## One soldier, 1.7 tall, marching: legs, tunic, arms, a rifle on the shoulder, a pack, a head and a spiked
## helmet; the first of a group carries the nation's flag.
static func _soldier(st: SurfaceTool, at: Vector3, uniform: Color, flag: Color, bearer: bool) -> void:
	var skin := Color(0.85, 0.7, 0.58)
	var trousers := uniform.darkened(0.22)
	var boots := Color(0.14, 0.1, 0.08)
	for z in [-0.14, 0.14]:
		block(st, at + Vector3(z * 0.9, 0, z), Vector3(0.22, 0.12, 0.3), boots)
		block(st, at + Vector3(z * 0.9, 0.12, z), Vector3(0.2, 0.7, 0.2), trousers)
	block(st, at + Vector3(0, 0.82, 0), Vector3(0.36, 0.62, 0.5), uniform)
	block(st, at + Vector3(0, 0.82, 0), Vector3(0.38, 0.1, 0.52), Color(0.25, 0.18, 0.12))
	block(st, at + Vector3(-0.28, 0.9, 0), Vector3(0.2, 0.5, 0.4), uniform.darkened(0.3))
	for z in [-0.33, 0.33]:
		block(st, at + Vector3(0.05, 0.9, z), Vector3(0.16, 0.5, 0.14), uniform.darkened(0.05))
	block(st, at + Vector3(0, 1.44, 0), Vector3(0.28, 0.28, 0.28), skin)
	block(st, at + Vector3(0, 1.66, 0), Vector3(0.34, 0.12, 0.34), uniform.darkened(0.4))
	CityParts.cone(st, at + Vector3(0, 1.78, 0), 0.05, 0.16, Color(0.8, 0.72, 0.4))
	CityParts.beam(st, at + Vector3(0.3, 0.75, 0.3), at + Vector3(-0.2, 1.75, 0.3), 0.08, Color(0.25, 0.18, 0.12))
	if bearer:
		CityParts.beam(st, at + Vector3(0.1, 0.8, -0.34), at + Vector3(0.1, 3.6, -0.34), 0.07, Color(0.2, 0.15, 0.1))
		block(st, at + Vector3(0.1, 2.5, -0.34), Vector3(0.04, 0.8, 1.1), flag)


## One horseman: a barrel body, neck, head and four legs, the rider with a cap, a sabre and a lance with a pennon.
static func _horseman(st: SurfaceTool, at: Vector3, uniform: Color) -> void:
	var shade := Color(0.42, 0.28, 0.18)
	block(st, at + Vector3(0, 1.0, 0), Vector3(2.0, 0.85, 0.75), shade)
	block(st, at + Vector3(1.05, 1.35, 0), Vector3(0.6, 0.95, 0.4), shade)
	block(st, at + Vector3(1.55, 1.9, 0), Vector3(0.75, 0.38, 0.36), shade.darkened(0.06))
	block(st, at + Vector3(-1.1, 1.2, 0), Vector3(0.12, 0.8, 0.12), shade.darkened(0.3))
	for lx in [-0.78, 0.78]:
		for lz in [-0.25, 0.25]:
			block(st, at + Vector3(lx, 0, lz), Vector3(0.18, 1.05, 0.18), shade.darkened(0.2))
	block(st, at + Vector3(-0.1, 1.85, 0), Vector3(0.45, 0.8, 0.42), uniform)
	block(st, at + Vector3(-0.1, 2.65, 0), Vector3(0.3, 0.3, 0.3), Color(0.85, 0.7, 0.58))
	block(st, at + Vector3(-0.1, 2.93, 0), Vector3(0.36, 0.14, 0.36), uniform.darkened(0.35))
	CityParts.beam(st, at + Vector3(-0.8, 1.5, 0.3), at + Vector3(1.8, 4.0, 0.3), 0.08, Color(0.3, 0.22, 0.14))
	block(st, at + Vector3(1.4, 3.7, 0.3), Vector3(0.5, 0.3, 0.04), Color(0.75, 0.2, 0.18))


## One field gun, three quarters of the size it would have beside the men so that it does not swamp them: a barrel
## on two wheels with a trail and a shield, and two gunners by it.
static func _gun(st: SurfaceTool, at: Vector3, uniform: Color) -> void:
	var k := 0.75
	var g := func(v: Vector3) -> Vector3: return at + v * k
	var metal := Color(0.38, 0.4, 0.36)
	var wood := Color(0.48, 0.36, 0.24)
	CityParts.beam(st, g.call(Vector3(-0.3, 1.1, 0)), g.call(Vector3(2.4, 1.45, 0)), 0.3 * k, metal)
	block(st, g.call(Vector3(0, 0.5, 0)), Vector3(1.2, 0.4, 0.7) * k, wood)
	block(st, g.call(Vector3(0.7, 0.9, 0)), Vector3(0.1, 0.8, 1.0) * k, metal.lightened(0.1))
	CityParts.beam(st, g.call(Vector3(-0.2, 0.6, 0)), g.call(Vector3(-2.2, 0.1, 0)), 0.28 * k, wood)
	for sz in [-0.55, 0.55]:
		var wheel: Vector3 = g.call(Vector3(0.1, 0.55, sz))
		for spoke: Vector3 in [Vector3(0.55, 0, 0), Vector3(0, 0.55, 0), Vector3(0.4, 0.4, 0), Vector3(0.4, -0.4, 0)]:
			CityParts.beam(st, wheel - spoke * k, wheel + spoke * k, 0.13 * k, wood)
	for crew: Vector3 in [Vector3(-1.4, 0, 1.0), Vector3(0.2, 0, -1.25)]:
		var c := at + crew
		block(st, c, Vector3(0.36, 0.8, 0.45), uniform.darkened(0.2))
		block(st, c + Vector3(0, 0.8, 0), Vector3(0.36, 0.62, 0.5), uniform)
		block(st, c + Vector3(0, 1.42, 0), Vector3(0.28, 0.28, 0.28), Color(0.85, 0.7, 0.58))
		block(st, c + Vector3(0, 1.64, 0), Vector3(0.34, 0.12, 0.34), uniform.darkened(0.4))


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


## A fleet's ships: at sea in line ahead, each pushing white water; moored (in port) side by side in rows of three, the
## block no longer than a few ships, so that it lies in a harbour.
static func fleet_mesh(line: Array, colour: Color, moored := false) -> ArrayMesh:
	var key := "f%s|%s|%s" % [colour.to_html(false), ",".join(PackedStringArray(line)), "m" if moored else ""]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wakes := SurfaceTool.new()
	wakes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := 0.0
	for type: String in line:
		total += _ship_length(type) + 5.0
	var x := -total * 0.5
	if moored:
		var longest := 0.0
		for type: String in line:
			longest = maxf(longest, _ship_length(type))
		var rows := ceili(line.size() / 3.0)
		for i in line.size():
			var row := i / 3
			var across := mini(3, line.size() - row * 3)
			_ship(st, Vector3((float(row) - (rows - 1) * 0.5) * (longest + 4.0), 0, (float(i % 3) - (across - 1) * 0.5) * 7.5), line[i], colour)
		line = []
	for i in line.size():
		var type: String = line[i]
		var length := _ship_length(type)
		x += length * 0.5
		var at := Vector3(x, 0, (float(i % 2) - 0.5) * 4.0)
		_wake(wakes, at, length, type)
		_ship(st, at, type, colour)
		x += length * 0.5 + 5.0
	var mesh := st.commit()
	# The second surface is the white water, see-through and fading away behind (its own material, wake_material).
	wakes.commit(mesh)
	mesh.surface_set_material(1, wake_material())
	_cache[key] = mesh
	return mesh


static var _wake_mat: StandardMaterial3D


## The see-through material of the white water round the ships: the colour and how solid it is come from the vertices.
static func wake_material() -> StandardMaterial3D:
	if _wake_mat == null:
		_wake_mat = StandardMaterial3D.new()
		_wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wake_mat.vertex_color_use_as_albedo = true
		_wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _wake_mat


## The white water a ship pushes, flat on the sea: a bow wave folding back from the stem along each side, and a wake
## widening behind the stern, both fading out as they go.
static func _wake(st: SurfaceTool, at: Vector3, length: float, type: String) -> void:
	var y := 0.08
	var beam := 2.2 if type in ["destroyer", "submarine"] else 4.0
	var solid := Color(0.9, 0.95, 0.97, 0.55)
	var clear := Color(0.9, 0.95, 0.97, 0.0)
	var stem := at + Vector3(length * 0.5, y, 0)
	for s: float in [-1.0, 1.0]:
		var side := at + Vector3(length * 0.25, y, s * beam * 0.5)
		var out := at + Vector3(-length * 0.05, y, s * (beam * 0.5 + 1.6))
		var hull := at + Vector3(-length * 0.05, y, s * beam * 0.5)
		_fan(st, [stem, side, out], [solid, solid, clear])
		_fan(st, [side, hull, out], [solid, clear, clear])
	var stern := at.x - length * 0.5
	var tail := length * 0.7
	_fan(st, [Vector3(stern, y, at.z + beam * 0.4), Vector3(stern, y, at.z - beam * 0.4), Vector3(stern - tail, y, at.z - beam * 1.1)], [solid, solid, clear])
	_fan(st, [Vector3(stern, y, at.z + beam * 0.4), Vector3(stern - tail, y, at.z - beam * 1.1), Vector3(stern - tail, y, at.z + beam * 1.1)], [solid, clear, clear])


## One triangle with a colour at each corner, facing up.
static func _fan(st: SurfaceTool, points: Array, colours: Array) -> void:
	for i in 3:
		st.set_normal(Vector3.UP)
		st.set_color(colours[i])
		st.add_vertex(points[i])


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
