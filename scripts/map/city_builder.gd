class_name CityBuilder
extends RefCounted
## Builds the mesh of one city (see CityModels): streets in a rotated grid, terraced houses and taller
## blocks, the landmarks of the place (data/landmarks.json) or else a church, a cathedral or a
## palace by its size, and what the province has: a harbour with quays, cranes and ships, a railway
## station with its tracks, a wall round the town where there are fortifications, and factory sheds
## with chimneys. Everything is in map pixels, centred on the city, and nothing is put where its
## foot would be in the sea.

const MAX_BUILDINGS := 520
const WALLS := [Color(0.89, 0.84, 0.72), Color(0.84, 0.76, 0.6), Color(0.8, 0.8, 0.76), Color(0.86, 0.78, 0.7), Color(0.76, 0.69, 0.58)]
const TILES := [Color(0.66, 0.31, 0.21), Color(0.58, 0.27, 0.19), Color(0.5, 0.36, 0.28)]
const SLATE := Color(0.34, 0.36, 0.4)
const STONE := Color(0.72, 0.7, 0.65)
const COPPER := Color(0.36, 0.52, 0.46)
const GOLD := Color(0.92, 0.76, 0.32)
const BRICK := Color(0.5, 0.28, 0.22)
const FOOT := CityParts.FOOT


## `info` says what the city has: name, chimneys (0 to 6), port (0 to 3), naval (a naval base), rail (0 to 5),
## fort (0 to 10). Returns {mesh, buildings, height, stacks (the tops of the chimneys, for smoke)}.
static func build(city_id: int, pop: int, info: Dictionary, capital: bool, centre: Vector2, is_land: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = city_id * 7919 + 17
	var pf := sqrt(float(pop) / 1000000.0)
	var radius := CityModels.radius_for(pop)
	var pitch := 4.4 + 0.5 * pf
	var turn := rng.randf() * PI
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var basis := Basis(Vector3.UP, turn)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tallest := 0.0
	var stacks: Array[Vector3] = []
	var limit_at := func(angle: float) -> float:
		return radius * (1.0 + 0.22 * sin(3.0 * angle + phase_a) + 0.12 * sin(5.0 * angle + phase_b))

	# --- the places set aside first, so that the houses keep clear of them: [{at, reach, kind, spec}]
	var features: Array[Dictionary] = []
	var landmarks: Array = CityLandmarks.for_city(str(info.get("name", "")))
	for spec: Dictionary in landmarks:
		var k := float(spec.get("k", 1.0))
		var reach := CityLandmarks.reach_of(str(spec.type)) * k
		var want := Vector3(float(spec.at[0]) * radius, -FOOT, float(spec.at[1]) * radius)
		var spot: Variant = _land_spot([want, want * 0.6, want * 0.3, Vector3.ZERO], centre, is_land, reach)
		if spot != null:
			features.append({"at": spot, "reach": reach, "kind": "landmark", "spec": spec})
	if landmarks.is_empty():
		var near := radius * 0.2
		if pop >= 12000:
			var k := 0.65 + 0.25 * pf if pop >= 250000 else 0.6 + 0.3 * pf
			var reach := 13.0 * k if pop >= 250000 else 7.5 * k
			var want := Vector3(rng.randf_range(-near, near), -FOOT, rng.randf_range(-near, near))
			var spot: Variant = _land_spot([want, Vector3.ZERO, Vector3(-near, -FOOT, near), Vector3(near, -FOOT, -near)], centre, is_land, reach)
			if spot != null:
				features.append({"at": spot, "reach": reach, "kind": "cathedral" if pop >= 250000 else "church", "k": k})
		if capital:
			var k := 0.65 + 0.2 * pf
			var spot: Variant = _land_spot([Vector3(radius * 0.28, -FOOT, -radius * 0.22), Vector3(-radius * 0.28, -FOOT, radius * 0.22), Vector3(0, -FOOT, radius * 0.3), Vector3(0, -FOOT, -radius * 0.3)], centre, is_land, 11.0 * k)
			if spot != null:
				features.append({"at": spot, "reach": 11.0 * k, "kind": "palace", "k": k})
	var inland := Vector2.ZERO          # the way from the sea toward the land, for stations
	var shore: Dictionary = _find_shore(centre, radius, is_land) if int(info.get("port", 0)) > 0 else {}
	if not shore.is_empty():
		inland = -shore.dir
		features.append({"at": Vector3(shore.point.x, -FOOT, shore.point.y), "reach": 12.0, "kind": "harbour"})
	var rail := int(info.get("rail", 0))
	var station_spot: Variant = null
	if rail > 0 and pop >= 20000:
		var away := inland if inland != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
		var want := Vector3(away.x * radius * 0.55, -FOOT, away.y * radius * 0.55)
		station_spot = _land_spot([want, want * 0.6, Vector3(-want.x, -FOOT, -want.z)], centre, is_land, 10.0)
		if station_spot != null:
			features.append({"at": station_spot, "reach": 10.0, "kind": "station"})

	# --- houses
	var span := int(ceil(radius * 1.35 / pitch)) + 1
	var spots: Array[Dictionary] = []
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			if i % 6 == 0 or j % 6 == 0:
				continue      # streets and squares
			var p := (Vector2(i, j) * pitch).rotated(turn)
			var d: float = p.length() / float(limit_at.call(atan2(p.y, p.x)))
			if d > 1.0:
				continue
			if rng.randf() < pow(d, 3.0) * 0.3:
				continue      # the edge thins out
			var blocked := false
			for f: Dictionary in features:
				if Vector2(f.at.x, f.at.z).distance_to(p) < float(f.reach) + 1.5:
					blocked = true
					break
			if not blocked:
				spots.append({"i": i, "j": j, "p": p, "d": d})
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var count := 0
	var half := pitch * 0.42
	for s: Dictionary in spots:
		if count >= MAX_BUILDINGS:
			break
		var p: Vector2 = s.p
		var foot_ok := true
		for corner in [Vector2(half, half), Vector2(-half, half), Vector2(half, -half), Vector2(-half, -half)]:
			if not is_land.call(centre + p + corner.rotated(turn) * 1.3):
				foot_ok = false
				break
		if not foot_ok:
			continue
		var core := 1.0 - float(s.d)
		var block := int(floorf((s.i + 2.0) / 6.0)) * 31 + int(floorf((s.j + 2.0) / 6.0)) * 17
		var level := mini(5, 1 + int(core * minf(2.2 + 1.2 * pf, 4.2)) + (absi(block) % 2))
		var walls: Color = WALLS[(absi(block) + (s.i + s.j) % 2) % WALLS.size()].lightened(rng.randf_range(-0.04, 0.05))
		var size := Vector3(pitch * rng.randf_range(0.84, 0.92), 2.2 + 1.2 * level + rng.randf_range(0.0, 0.5), pitch * rng.randf_range(0.86, 0.93))
		var at := Vector3(p.x, -FOOT, p.y)
		CityParts.box(st, at, Vector3(size.x, size.y + FOOT, size.z), walls, basis)
		var top := at + Vector3(0, size.y + FOOT, 0)
		if level <= 2:
			var roof: Color = TILES[(absi(block) + s.i) % TILES.size()].lightened(rng.randf_range(-0.04, 0.05))
			CityParts.gable(st, top, Vector3(size.x * 1.08, size.x * 0.42, size.z * 1.06), roof, basis, (absi(block) % 2) == 0)
			tallest = maxf(tallest, size.y + size.x * 0.42)
		else:
			CityParts.box(st, top, Vector3(size.x * 1.04, 0.7, size.z * 1.04), SLATE.lightened(rng.randf_range(0.0, 0.1)), basis)
			tallest = maxf(tallest, size.y + 0.7)
		count += 1

	# --- the places themselves
	for f: Dictionary in features:
		match str(f.kind):
			"landmark":
				tallest = maxf(tallest, CityLandmarks.build(st, f.spec, f.at))
			"cathedral":
				tallest = maxf(tallest, _cathedral(st, f.at, basis, float(f.k)))
			"church":
				tallest = maxf(tallest, _church(st, f.at, basis, float(f.k)))
			"palace":
				tallest = maxf(tallest, _palace(st, f.at, basis, float(f.k)))
			"harbour":
				tallest = maxf(tallest, _harbour(st, shore, centre, is_land, int(info.port), bool(info.get("naval", false)), pf, rng))
			"station":
				tallest = maxf(tallest, _station(st, f.at, centre, is_land, rail, radius, rng))
	var fort := int(info.get("fort", 0))
	if fort > 0:
		_walls(st, centre, is_land, limit_at, fort, rng)
	for k in int(info.get("chimneys", 0)):
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.55, 0.9)
		var at := Vector3(cos(a) * r, -FOOT, sin(a) * r)
		if _land_spot([at], centre, is_land, 10.0) == null:
			continue
		CityParts.box(st, at, Vector3(14.0, 4.0 + FOOT, 6.0), BRICK.lightened(0.08), basis)
		CityParts.gable(st, at + Vector3(0, 4.0 + FOOT, 0), Vector3(14.5, 3.0, 6.4), SLATE, basis, true)
		var stack_at := at + Vector3(6.0, 0, 1.5)
		var stack_h := 4.0 + FOOT + rng.randf_range(10.0, 16.0)
		CityParts.cylinder(st, stack_at, 0.9, stack_h, BRICK)
		stacks.append(stack_at + Vector3(0, stack_h, 0))
		tallest = maxf(tallest, 14.0 + 4.0)
	return {"mesh": st.commit(), "buildings": count, "height": tallest, "stacks": stacks}


## The first of the candidate spots (offsets from the city's middle, y ignored) whose whole foot, a square
## of `reach` pixels about it, is on land; null if none.
static func _land_spot(spots: Array, centre: Vector2, is_land: Callable, reach: float) -> Variant:
	for at: Vector3 in spots:
		var here := centre + Vector2(at.x, at.z)
		var ok := true
		for corner in [Vector2.ZERO, Vector2(reach, reach), Vector2(-reach, reach), Vector2(reach, -reach), Vector2(-reach, -reach)]:
			if not is_land.call(here + corner):
				ok = false
				break
		if ok:
			return at
	return null


## Where the shore is, if the sea comes near: {dir (toward the sea), point (the last land on that line), dist}.
static func _find_shore(centre: Vector2, radius: float, is_land: Callable) -> Dictionary:
	var best := {}
	for i in 32:
		var dir := Vector2.from_angle(TAU * i / 32.0)
		var r := radius * 0.4
		while r < radius * 1.7:
			if not is_land.call(centre + dir * r):
				break
			r += 2.0
		if r < radius * 1.7 and (best.is_empty() or r < best.dist):
			best = {"dir": dir, "point": dir * (r - 3.0), "dist": r}
	return best


static func _church(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var nave := Vector3(5.0 * k, 5.5 * k + FOOT, 11.0 * k)
	CityParts.box(st, at, nave, STONE, basis)
	CityParts.gable(st, at + basis * Vector3(0, nave.y, 0), Vector3(5.4 * k, 3.0 * k, 11.2 * k), SLATE, basis, false)
	var tower_at := at + basis * Vector3(0, 0, 6.2 * k)
	var tower := Vector3(3.4 * k, 12.0 * k + FOOT, 3.4 * k)
	CityParts.box(st, tower_at, tower, STONE.darkened(0.05), basis)
	CityParts.cone(st, tower_at + Vector3(0, tower.y, 0), 2.3 * k, 10.0 * k, SLATE.darkened(0.1))
	return tower.y + 10.0 * k - FOOT


static func _cathedral(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var nave := Vector3(8.0 * k, 8.5 * k + FOOT, 20.0 * k)
	CityParts.box(st, at, nave, STONE, basis)
	CityParts.gable(st, at + basis * Vector3(0, nave.y, 0), Vector3(8.6 * k, 4.5 * k, 20.4 * k), COPPER, basis, false)
	CityParts.box(st, at, Vector3(20.0 * k, 6.0 * k + FOOT, 6.0 * k), STONE.darkened(0.04), basis)
	var best := 0.0
	for side in [-1.0, 1.0]:
		var tower_at := at + basis * Vector3(side * 2.6 * k, 0, 11.4 * k)
		var tower := Vector3(3.6 * k, 20.0 * k + FOOT, 3.6 * k)
		CityParts.box(st, tower_at, tower, STONE.darkened(0.06), basis)
		CityParts.cone(st, tower_at + Vector3(0, tower.y, 0), 2.6 * k, 12.0 * k, COPPER)
		best = tower.y + 12.0 * k - FOOT
	return best


static func _palace(st: SurfaceTool, at: Vector3, basis: Basis, k: float) -> float:
	var base := Vector3(16.0 * k, 8.0 * k + FOOT, 16.0 * k)
	CityParts.box(st, at, base, STONE.lightened(0.06), basis)
	CityParts.box(st, at + Vector3(0, base.y, 0), Vector3(17.0 * k, 1.0, 17.0 * k), STONE.darkened(0.12), basis)
	var drum_at := at + Vector3(0, base.y + 1.0, 0)
	CityParts.cylinder(st, drum_at, 5.5 * k, 5.0 * k, STONE)
	CityParts.cone(st, drum_at + Vector3(0, 5.0 * k, 0), 5.8 * k, 5.5 * k, GOLD.darkened(0.1))
	CityParts.cone(st, drum_at + Vector3(0, 10.0 * k, 0), 1.2 * k, 5.0 * k, GOLD)
	return base.y + 1.0 + 15.0 * k - FOOT


## A harbour on the shore: a stone quay along it, warehouses behind, cranes on the quay and ships in the
## water, more of them the bigger the port; grey warships if the nation keeps a naval base there.
static func _harbour(st: SurfaceTool, shore: Dictionary, centre: Vector2, is_land: Callable, level: int, naval: bool, pf: float, rng: RandomNumberGenerator) -> float:
	var dir: Vector2 = shore.dir
	var tangent := Vector2(-dir.y, dir.x)
	var origin: Vector2 = shore.point
	var length := 18.0 + 8.0 * level + 10.0 * pf
	var best := 0.0
	var quay_stone := Color(0.5, 0.48, 0.44)
	var sheds := 2 + level
	for i in sheds:
		var along := (float(i) / maxf(1.0, sheds - 1) - 0.5) * length
		var p := origin - dir * 7.0 + tangent * along
		if is_land.call(centre + p + dir * 2.0) and is_land.call(centre + p - dir * 4.0):
			var basis := Basis(Vector3.UP, -tangent.angle())
			CityParts.box(st, Vector3(p.x, -FOOT, p.y), Vector3(7.0, 3.5 + FOOT, 4.0), CityParts.WALLS_PORT[i % 3], basis)
			CityParts.gable(st, Vector3(p.x, 3.5, p.y), Vector3(7.4, 2.0, 4.4), SLATE, basis, true)
	for step in 12:
		var along := (float(step) / 11.0 - 0.5) * length
		var a := origin + tangent * (along - length / 24.0)
		var b := origin + tangent * (along + length / 24.0)
		if is_land.call(centre + a + dir * 1.5) or is_land.call(centre + a - dir * 1.5):
			CityParts.strip(st, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), 4.5, quay_stone, 0.9)
	var cranes := mini(4, 1 + level)
	for i in cranes:
		var along := (float(i) / maxf(1.0, cranes - 1) - 0.5) * length * 0.8 if cranes > 1 else 0.0
		var p := origin + tangent * along - dir * 1.5
		if not is_land.call(centre + p):
			continue
		var base := Vector3(p.x, 0.9, p.y)
		var seaward := Vector3(dir.x, 0, dir.y)
		CityParts.box(st, base, Vector3(2.2, 5.0, 2.2), Color(0.35, 0.37, 0.4))
		CityParts.beam(st, base + Vector3(0, 5.0, 0), base + Vector3(0, 9.0, 0) + seaward * 5.0, 0.7, Color(0.45, 0.2, 0.17))
		CityParts.beam(st, base + Vector3(0, 9.0, 0) + seaward * 5.0, base + Vector3(0, 5.0, 0) - seaward * 3.0, 0.5, Color(0.45, 0.2, 0.17))
		best = maxf(best, 9.5)
	var ships := mini(4, 1 + level + int(pf))
	for i in ships:
		var along := (float(i) - (ships - 1) * 0.5) * 11.0
		var p := origin + tangent * along + dir * (6.5 + 2.5 * (i % 2))
		if is_land.call(centre + p) or is_land.call(centre + p + dir * 4.0) or is_land.call(centre + p + tangent * 6.0):
			continue
		_ship(st, Vector3(p.x, -1.2, p.y), Basis(Vector3.UP, -tangent.angle() + rng.randf_range(-0.1, 0.1)), naval, rng)
		best = maxf(best, 7.0)
	return best


## A ship: a hull with a pointed bow, a deckhouse, a funnel, and for a warship two turrets.
static func _ship(st: SurfaceTool, at: Vector3, basis: Basis, warship: bool, rng: RandomNumberGenerator) -> void:
	var hull_colour := Color(0.42, 0.45, 0.5) if warship else Color(0.16, 0.17, 0.2)
	var length := 13.0 if warship else 11.0
	CityParts.box(st, at, Vector3(length, 2.2, 3.2), hull_colour, basis)
	var bow := at + basis * Vector3(length * 0.5, 0, 0)
	CityParts.tri(st, bow + basis * Vector3(0, 2.2, 1.6), bow + basis * Vector3(0, 2.2, -1.6), bow + basis * Vector3(2.6, 2.2, 0), hull_colour.lightened(0.05))
	CityParts.tri(st, bow + basis * Vector3(0, 0, -1.6), bow + basis * Vector3(0, 0, 1.6), bow + basis * Vector3(2.6, 0, 0), hull_colour.darkened(0.1))
	CityParts.box(st, at + basis * Vector3(-length * 0.12, 2.2, 0), Vector3(4.0, 1.8, 2.4), Color(0.86, 0.85, 0.8), basis)
	CityParts.cylinder(st, at + basis * Vector3(-length * 0.12, 4.0, 0), 0.7, 2.6, Color(0.8, 0.25, 0.2) if not warship else Color(0.3, 0.3, 0.33))
	if warship:
		for x in [-1.0, 1.0]:
			CityParts.box(st, at + basis * Vector3(x * length * 0.3, 2.2, 0), Vector3(2.0, 1.0, 2.0), hull_colour.darkened(0.1), basis)
			CityParts.beam(st, at + basis * Vector3(x * length * 0.3, 2.9, 0), at + basis * Vector3(x * length * 0.3 + 2.4, 3.1, 0), 0.4, Color(0.2, 0.2, 0.22))


## A railway station with its tracks: a long hall with a glass-grey roof and a clock tower, and track going out
## across the land (as far as it is land) the way the hall lies, more of it the more railway the province has.
static func _station(st: SurfaceTool, at: Vector3, centre: Vector2, is_land: Callable, rail: int, radius: float, rng: RandomNumberGenerator) -> float:
	var angle := rng.randf() * PI
	var basis := Basis(Vector3.UP, angle)
	CityParts.box(st, at, Vector3(16.0, 5.0 + FOOT, 6.5), Color(0.74, 0.66, 0.55), basis)
	CityParts.gable(st, at + Vector3(0, 5.0, 0), Vector3(16.4, 3.6, 6.9), Color(0.45, 0.52, 0.56), basis, true)
	CityParts.box(st, at + basis * Vector3(-5.0, 0, 3.6), Vector3(3.0, 10.0 + FOOT, 3.0), Color(0.74, 0.66, 0.55), basis)
	CityParts.cone(st, at + basis * Vector3(-5.0, 10.0, 3.6), 2.2, 3.5, SLATE)
	var along := Vector2.from_angle(angle)
	var rails := 2 + mini(rail, 3)
	# The tracks run out of the hall to the edge of the town, not across the country (the town stands on one level, the
	# land around it does not): a gravel bed with a pair of rails on it.
	for t in rails:
		var offset := (float(t) - (rails - 1) * 0.5) * 1.8
		var side := Vector2(-along.y, along.x)
		for direction: float in [-1.0, 1.0]:
			var start := Vector2(at.x, at.z) + side * (offset - 4.0) + along * direction * 8.0
			var step := along * direction * 4.0
			var p := start
			for n in int(radius * 0.5 / 4.0) + 2:
				var q := p + step
				if not (is_land.call(centre + p) and is_land.call(centre + q)):
					break
				CityParts.strip(st, Vector3(p.x, 0, p.y), Vector3(q.x, 0, q.y), 1.1, Color(0.5, 0.46, 0.41), 0.3)
				for r: float in [-0.3, 0.3]:
					var o: Vector2 = side * r
					CityParts.strip(st, Vector3(p.x + o.x, 0, p.y + o.y), Vector3(q.x + o.x, 0, q.y + o.y), 0.12, Color(0.24, 0.22, 0.21), 0.36)
				p = q
	return 10.0 + 3.5


## A wall round the town, a little outside the houses, with a tower every few sections, and from fortification
## level 3 a bastion at some of the corners; no wall where there is sea.
static func _walls(st: SurfaceTool, centre: Vector2, is_land: Callable, limit_at: Callable, fort: int, rng: RandomNumberGenerator) -> void:
	var sections := 30
	var stone := Color(0.62, 0.6, 0.55)
	var height := 3.0 + 0.5 * mini(fort, 6)
	for i in sections:
		var a0 := TAU * i / sections
		var a1 := TAU * (i + 1) / sections
		var p0 := Vector2.from_angle(a0) * float(limit_at.call(a0)) * 1.1
		var p1 := Vector2.from_angle(a1) * float(limit_at.call(a1)) * 1.1
		if not (is_land.call(centre + p0) and is_land.call(centre + p1)):
			continue
		var mid := (p0 + p1) * 0.5
		var length := p0.distance_to(p1)
		var basis := Basis(Vector3.UP, -(p1 - p0).angle())
		CityParts.box(st, Vector3(mid.x, -FOOT, mid.y), Vector3(length, height + FOOT, 1.2), stone, basis)
		if i % 3 == 0:
			CityParts.cylinder(st, Vector3(p0.x, -FOOT, p0.y), 1.7, height + 3.0 + FOOT, stone.darkened(0.05))
			CityParts.cone(st, Vector3(p0.x, height + 3.0, p0.y), 2.0, 2.8, Color(0.4, 0.32, 0.3))
		if fort >= 3 and i % 6 == 3:
			var out := p0.normalized()
			var bastion := p0 + out * 3.5
			if is_land.call(centre + bastion):
				CityParts.frustum(st, Vector3(bastion.x, -FOOT, bastion.y), Vector2(4.0, 4.0), Vector2(3.0, 3.0), height + FOOT + 1.0, stone.darkened(0.08), Basis(Vector3.UP, -out.angle()))
