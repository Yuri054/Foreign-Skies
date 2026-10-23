class_name CityParts
extends RefCounted
## The shapes the city models are made of, drawn into a SurfaceTool with a colour for every
## vertex: boxes, pitched roofs, cylinders, cones, and the turned shapes (domes, onions, spires)
## and frames that the landmarks use. Everything is in map pixels, y up, a shape's base on
## `base` and turned by `basis` where it takes one.

## How deep the walls reach below the ground the city stands on, so that hills do not show gaps.
const FOOT := 4.0
## Colours of the sheds on a quay.
const WALLS_PORT := [Color(0.62, 0.45, 0.36), Color(0.7, 0.66, 0.58), Color(0.5, 0.42, 0.38)]


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(st, a, b, c, color)
	tri(st, a, c, d, color)


## A box standing on `base` (the middle of its foot), `size` wide, tall and deep, turned by `basis`. The
## walls are a shade darker near the ground.
static func box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var low := minf(size.y, CityParts.FOOT + 2.2)
	var c := func(x: float, y: float, z: float) -> Vector3: return base + basis * Vector3(x, y, z)
	var p000: Vector3 = c.call(-hx, 0.0, -hz)
	var p100: Vector3 = c.call(hx, 0.0, -hz)
	var p101: Vector3 = c.call(hx, 0.0, hz)
	var p001: Vector3 = c.call(-hx, 0.0, hz)
	var m000: Vector3 = c.call(-hx, low, -hz)
	var m100: Vector3 = c.call(hx, low, -hz)
	var m101: Vector3 = c.call(hx, low, hz)
	var m001: Vector3 = c.call(-hx, low, hz)
	var q000: Vector3 = c.call(-hx, size.y, -hz)
	var q100: Vector3 = c.call(hx, size.y, -hz)
	var q101: Vector3 = c.call(hx, size.y, hz)
	var q001: Vector3 = c.call(-hx, size.y, hz)
	var shade := color.darkened(0.14)
	quad(st, p001, p101, m101, m001, shade)
	quad(st, p100, p000, m000, m100, shade.darkened(0.06))
	quad(st, p101, p100, m100, m101, shade.darkened(0.03))
	quad(st, p000, p001, m001, m000, shade.darkened(0.1))
	quad(st, m001, m101, q101, q001, color)
	quad(st, m100, m000, q000, q100, color.darkened(0.08))
	quad(st, m101, m100, q100, q101, color.darkened(0.04))
	quad(st, m000, m001, q001, q000, color.darkened(0.12))
	quad(st, q001, q101, q100, q000, color.lightened(0.04))


## A pitched roof on a building: `size.y` is the ridge's rise, the ridge along the building's x or z.
static func gable(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, basis: Basis, along_x: bool) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := size.y
	var c := func(x: float, y: float, z: float) -> Vector3: return base + basis * Vector3(x, y, z)
	var a: Vector3 = c.call(-hx, 0.0, -hz)
	var b: Vector3 = c.call(hx, 0.0, -hz)
	var cc: Vector3 = c.call(hx, 0.0, hz)
	var d: Vector3 = c.call(-hx, 0.0, hz)
	if along_x:
		var r0: Vector3 = c.call(-hx, top, 0.0)
		var r1: Vector3 = c.call(hx, top, 0.0)
		quad(st, d, cc, r1, r0, color)
		quad(st, b, a, r0, r1, color.darkened(0.14))
		tri(st, a, d, r0, color.darkened(0.22))
		tri(st, cc, b, r1, color.darkened(0.22))
	else:
		var r0: Vector3 = c.call(0.0, top, -hz)
		var r1: Vector3 = c.call(0.0, top, hz)
		quad(st, cc, b, r0, r1, color.darkened(0.04))
		quad(st, a, d, r1, r0, color.darkened(0.16))
		tri(st, d, cc, r1, color.darkened(0.22))
		tri(st, b, a, r0, color.darkened(0.22))


static func cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		var t0 := p0 + Vector3(0, height, 0)
		var t1 := p1 + Vector3(0, height, 0)
		quad(st, p1, p0, t0, t1, color.darkened(0.05 * float(i % 3)))
		tri(st, t0, Vector3(base.x, base.y + height, base.z), t1, color.lightened(0.05))


static func cone(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 8
	var tip := base + Vector3(0, height, 0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		tri(st, p1, p0, tip, color.darkened(0.07 * float(i % 3)))


## A box that narrows toward the top: `bottom` and `top` are the half-widths (x, z) of its foot and its head.
static func frustum(st: SurfaceTool, base: Vector3, bottom: Vector2, top: Vector2, height: float, color: Color, basis := Basis.IDENTITY) -> void:
	var c := func(x: float, y: float, z: float) -> Vector3: return base + basis * Vector3(x, y, z)
	var b00: Vector3 = c.call(-bottom.x, 0.0, -bottom.y)
	var b10: Vector3 = c.call(bottom.x, 0.0, -bottom.y)
	var b11: Vector3 = c.call(bottom.x, 0.0, bottom.y)
	var b01: Vector3 = c.call(-bottom.x, 0.0, bottom.y)
	var t00: Vector3 = c.call(-top.x, height, -top.y)
	var t10: Vector3 = c.call(top.x, height, -top.y)
	var t11: Vector3 = c.call(top.x, height, top.y)
	var t01: Vector3 = c.call(-top.x, height, top.y)
	quad(st, b01, b11, t11, t01, color)
	quad(st, b10, b00, t00, t10, color.darkened(0.1))
	quad(st, b11, b10, t10, t11, color.darkened(0.04))
	quad(st, b00, b01, t01, t00, color.darkened(0.14))
	quad(st, t01, t11, t10, t00, color.lightened(0.04))


## A turned shape (a dome, an onion, a spire) from a profile of (radius, height) points from the bottom up,
## standing on `base`; `sides` is the number of flat faces round it. A profile that ends at radius 0 closes
## in a point.
static func revolve(st: SurfaceTool, base: Vector3, profile: Array, sides: int, color: Color) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var v00 := base + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := base + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := base + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := base + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var shade := color.darkened(0.07 * float(k % 3)).lightened(0.03 * (float(i) / maxf(1.0, profile.size())))
			if p1.x <= 0.001:
				tri(st, v01, v00, v10, shade)
			elif p0.x <= 0.001:
				tri(st, v01, v11, v10, shade)
			else:
				quad(st, v01, v00, v10, v11, shade)


## A dome of the given radius and height: a flattened half-sphere on a short rim.
static func dome(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var profile: Array = [Vector2(radius, 0.0)]
	for k in range(1, 7):
		var a := PI * 0.5 * k / 6.0
		profile.append(Vector2(radius * cos(a), height * sin(a)))
	revolve(st, base, profile, 12, color)


## An onion dome: a bulb that swells above its neck and ends in a point.
static func onion(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var profile: Array = [Vector2(radius * 0.55, 0.0), Vector2(radius * 0.7, height * 0.12), Vector2(radius * 1.05, height * 0.34),
			Vector2(radius * 1.0, height * 0.5), Vector2(radius * 0.7, height * 0.7), Vector2(radius * 0.3, height * 0.88), Vector2(0.0, height)]
	revolve(st, base, profile, 10, color)


## A tall thin spire: a long needle on a square or round foot.
static func spire(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	var profile: Array = [Vector2(radius, 0.0), Vector2(radius * 0.8, height * 0.35), Vector2(radius * 0.5, height * 0.7), Vector2(radius * 0.16, height * 0.92), Vector2(0.0, height)]
	revolve(st, base, profile, 6, color)


## A ring of wall (a round or oval building without a roof, a colosseum): `radius` is x and z, thickness in
## pixels, with a darker band every `band` pixels of height.
static func ring(st: SurfaceTool, base: Vector3, radius: Vector2, thickness: float, height: float, color: Color, basis := Basis.IDENTITY, segments := 20) -> void:
	for k in segments:
		var a0 := TAU * k / segments
		var a1 := TAU * (k + 1) / segments
		var o0 := Vector3(cos(a0) * radius.x, 0.0, sin(a0) * radius.y)
		var o1 := Vector3(cos(a1) * radius.x, 0.0, sin(a1) * radius.y)
		var i0 := Vector3(cos(a0) * (radius.x - thickness), 0.0, sin(a0) * (radius.y - thickness))
		var i1 := Vector3(cos(a1) * (radius.x - thickness), 0.0, sin(a1) * (radius.y - thickness))
		var up := Vector3(0, height, 0)
		var shade := color.darkened(0.05 * float(k % 2))
		quad(st, base + basis * o1, base + basis * o0, base + basis * (o0 + up), base + basis * (o1 + up), shade)
		quad(st, base + basis * i0, base + basis * i1, base + basis * (i1 + up), base + basis * (i0 + up), shade.darkened(0.18))
		quad(st, base + basis * (o0 + up), base + basis * (i0 + up), base + basis * (i1 + up), base + basis * (o1 + up), color.lightened(0.05))


## A flat dark strip on the ground, for rails, quays and roads: from `a` to `b`, `width` across.
static func strip(st: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color, lift := 0.15) -> void:
	var along := (b - a)
	if along.length() < 0.01:
		return
	var side := Vector3(-along.z, 0.0, along.x).normalized() * width * 0.5
	var up := Vector3(0, lift, 0)
	quad(st, a - side + up, a + side + up, b + side + up, b - side + up, color)


## A thin beam between two points (a strut, a rail, a spoke), `thick` across, drawn as a long box.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.01:
		return
	var forward := along / length
	var helper := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
	var side := forward.cross(helper).normalized() * thick * 0.5
	var up := forward.cross(side).normalized() * thick * 0.5
	var a0 := a - side - up
	var a1 := a + side - up
	var a2 := a + side + up
	var a3 := a - side + up
	var b0 := b - side - up
	var b1 := b + side - up
	var b2 := b + side + up
	var b3 := b - side + up
	quad(st, a0, a1, b1, b0, color.darkened(0.1))
	quad(st, a1, a2, b2, b1, color)
	quad(st, a2, a3, b3, b2, color.lightened(0.05))
	quad(st, a3, a0, b0, b3, color.darkened(0.15))
