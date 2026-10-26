class_name Lightning
extends Node3D
## A cosmetic lightning strike on the 3D map: a thick, branching bolt with a glow, two smaller
## side strikes, a shockwave, sparks, smoke, a scorch and a camera punch. Pure spectacle: it reads
## and writes no game state, and frees itself when the storm is over.
##
## `strike(parent, ground, camera, ui)` adds one to `parent` at `ground` (a point on the 3D map).
## The map's plane is only 16 by 9 units, so the bolt is a few units tall rather than world-scale.

const BOLT_HEIGHT := 4.8
const BOLT_WIDTH := 0.045
const GLOW_WIDTH := 0.1
const HALO_WIDTH := 0.2
const BOLT_LIFE := 0.7
const SCORCH_LIFE := 4.5
const TOTAL_LIFE := 7.0
const BASE_FOV := 50.0

const CORE_COLOR := Color(0.96, 0.99, 1.0)
const GLOW_COLOR := Color(0.35, 0.62, 1.0)
const FLASH_COLOR := Color(0.62, 0.8, 1.0)


static func strike(parent: Node3D, ground: Vector3, camera: Camera3D, ui: CanvasLayer = null) -> Node3D:
	var effect := Lightning.new()
	effect.position = ground
	parent.add_child(effect)
	effect._build(camera, ui)
	return effect


func _build(camera: Camera3D, ui: CanvasLayer) -> void:
	_build_bolt(camera)
	_build_lights()
	_build_impact()
	_build_sparks()
	_build_scorch()
	_build_screen_flash(ui)
	_punch_camera(camera)
	get_tree().create_timer(TOTAL_LIFE).timeout.connect(queue_free)


# ------------------------------------------------------------------ the bolt

func _build_bolt(camera: Camera3D) -> void:
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	add_child(bolt)

	var core_mesh := ImmediateMesh.new()
	var glow_mesh := ImmediateMesh.new()
	var halo_mesh := ImmediateMesh.new()
	var core_material := _bolt_material(CORE_COLOR, 10.0, false)
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	core_material.render_priority = 3
	var glow_material := _bolt_material(GLOW_COLOR, 4.0, true)
	glow_material.albedo_color.a = 0.26
	glow_material.render_priority = 2
	var halo_material := _bolt_material(Color(0.3, 0.55, 1.0), 1.5, true)
	halo_material.albedo_color.a = 0.04
	halo_material.render_priority = 1
	core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, core_material)
	glow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, glow_material)
	halo_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, halo_material)

	var main := _fractal(Vector3(randf_range(-0.35, 0.35), BOLT_HEIGHT, randf_range(-0.35, 0.35)), Vector3.ZERO, 0.32, 5)
	_add_ribbon(core_mesh, main, camera, BOLT_WIDTH)
	_add_ribbon(glow_mesh, main, camera, GLOW_WIDTH)
	_add_ribbon(halo_mesh, main, camera, HALO_WIDTH)

	# Two short forks off the main channel, not a web.
	for i in 2:
		var from: Vector3 = main[randi_range(5, main.size() - 5)]
		var end := from + Vector3(randf_range(-0.9, 0.9), -randf_range(0.45, 1.0), randf_range(-0.9, 0.9))
		end.y = maxf(end.y, 0.0)
		var branch := _fractal(from, end, 0.35, 4)
		_add_ribbon(core_mesh, branch, camera, BOLT_WIDTH * 0.5)
		_add_ribbon(glow_mesh, branch, camera, GLOW_WIDTH * 0.42)
		_add_ribbon(halo_mesh, branch, camera, HALO_WIDTH * 0.36)

	# The forks are enough: one main channel makes a stronger bolt than a web of side strikes.

	core_mesh.surface_end()
	glow_mesh.surface_end()
	halo_mesh.surface_end()
	var core := MeshInstance3D.new()
	core.name = "BoltCore"
	core.mesh = core_mesh
	core.material_override = core_material
	bolt.add_child(core)
	var glow := MeshInstance3D.new()
	glow.name = "BoltGlow"
	glow.mesh = glow_mesh
	glow.material_override = glow_material
	bolt.add_child(glow)
	var halo := MeshInstance3D.new()
	halo.name = "BoltHalo"
	halo.mesh = halo_mesh
	halo.material_override = halo_material
	bolt.add_child(halo)

	# Return strokes: the bolt stutters, then the channel cools and fades.
	var tween := create_tween()
	tween.tween_interval(0.05)
	tween.tween_callback(func() -> void: bolt.visible = false)
	tween.tween_interval(0.03)
	tween.tween_callback(func() -> void: bolt.visible = true)
	tween.tween_interval(0.06)
	tween.tween_callback(func() -> void: bolt.visible = false)
	tween.tween_interval(0.04)
	tween.tween_callback(func() -> void: bolt.visible = true)
	tween.tween_interval(0.05)
	tween.tween_callback(func() -> void: bolt.visible = false)
	tween.tween_interval(0.035)
	tween.tween_callback(func() -> void: bolt.visible = true)
	tween.tween_property(glow_material, "albedo_color:a", 0.0, BOLT_LIFE)
	tween.parallel().tween_property(halo_material, "albedo_color:a", 0.0, BOLT_LIFE)
	tween.tween_callback(func() -> void: bolt.visible = false)


func _bolt_material(color: Color, energy: float, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A jagged, natural bolt through midpoint displacement: each segment is split, its middle
## pushed sideways, and the push shrinks with each level. Ends are exact.
func _fractal(from: Vector3, to: Vector3, roughness: float, levels: int) -> Array[Vector3]:
	var points: Array[Vector3] = [from, to]
	var amount := (to - from).length() * roughness
	for level in levels:
		var next: Array[Vector3] = []
		for i in points.size() - 1:
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			var side := dir.cross(Vector3.UP)
			if side.length_squared() < 0.001:
				side = Vector3.RIGHT
			side = side.normalized()
			mid += side * randf_range(-amount, amount)
			mid += Vector3(randf_range(-amount * 0.35, amount * 0.35), 0, randf_range(-amount * 0.35, amount * 0.35))
			next.append(a)
			next.append(mid)
		next.append(points[points.size() - 1])
		points = next
		amount *= 0.55
	return points


## A continuous camera-facing ribbon along `points` (shared side vertices, so no flat segment ends).
func _add_ribbon(mesh: ImmediateMesh, points: Array[Vector3], camera: Camera3D, width: float) -> void:
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in points.size():
		var a: Vector3 = points[maxi(i - 1, 0)]
		var b: Vector3 = points[mini(i + 1, points.size() - 1)]
		var view := camera.global_position - (global_position + points[i]) if camera != null else Vector3(0, 0, 1)
		var side := (b - a).cross(view)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * width
		lefts.append(points[i] - side)
		rights.append(points[i] + side)
	for i in points.size() - 1:
		for v: Vector3 in [lefts[i], rights[i], rights[i + 1], lefts[i], rights[i + 1], lefts[i + 1]]:
			mesh.surface_add_vertex(v)


# ------------------------------------------------------------------ light and impact

func _build_lights() -> void:
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.position = Vector3(0, 1.2, 0)
	flash.light_color = FLASH_COLOR
	flash.light_energy = 8.0
	flash.omni_range = 8.0
	flash.shadow_enabled = false
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.5)

	var sky := OmniLight3D.new()
	sky.name = "SkyFlash"
	sky.position = Vector3(0, BOLT_HEIGHT * 0.8, 0)
	sky.light_color = Color(0.58, 0.76, 1.0)
	sky.light_energy = 4.5
	sky.omni_range = 18.0
	sky.shadow_enabled = false
	add_child(sky)
	var sky_tween := create_tween()
	sky_tween.tween_property(sky, "light_energy", 0.0, 0.35)

	var sun := DirectionalLight3D.new()
	sun.name = "SkyBurst"
	sun.light_color = Color(0.75, 0.86, 1.0)
	sun.light_energy = 1.8
	sun.rotation_degrees = Vector3(-68.0, -24.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	var sun_tween := create_tween()
	sun_tween.tween_property(sun, "light_energy", 0.0, 0.22)


func _build_impact() -> void:
	# A hot disc on the ground (a flat cylinder, so it stays round without a texture).
	var disc := MeshInstance3D.new()
	disc.name = "ImpactDisc"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.01
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.position = Vector3(0, 0.03, 0)
	var disc_material := _glow_material(Color(0.35, 0.65, 1.0, 0.45), true)
	disc_material.no_depth_test = false
	disc.material_override = disc_material
	disc.scale = Vector3(0.3, 1.0, 0.3)
	add_child(disc)
	var disc_tween := create_tween()
	disc_tween.tween_property(disc, "scale", Vector3(1.0, 1.0, 1.0), 0.45)
	disc_tween.parallel().tween_property(disc_material, "albedo_color:a", 0.0, 0.45)

	# A real torus shockwave running out from the point of impact.
	var ring := MeshInstance3D.new()
	ring.name = "Shockwave"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.7
	ring_mesh.outer_radius = 0.85
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.06, 0)
	var ring_material := _glow_material(Color(0.75, 0.9, 1.0, 0.75), true)
	ring_material.no_depth_test = false
	ring.material_override = ring_material
	ring.scale = Vector3(0.3, 1.0, 0.3)
	add_child(ring)
	var ring_tween := create_tween()
	ring_tween.tween_property(ring, "scale", Vector3(4.0, 1.0, 4.0), 0.55)
	ring_tween.parallel().tween_property(ring_material, "albedo_color:a", 0.0, 0.55)

func _build_sparks() -> void:
	var sparks := _particles(80, 1.0, 1.0, 2.5, 9.0, 0.4, 1.0, Color(0.75, 0.9, 1.0, 1.0))
	sparks.name = "Sparks"
	sparks.position = Vector3(0, 0.15, 0)
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.mesh = _spark_mesh(Color(0.75, 0.9, 1.0, 1.0))
	add_child(sparks)
	sparks.emitting = true


func _particles(amount: int, lifetime: float, explosiveness: float, speed_min: float, speed_max: float, scale_min: float, scale_max: float, color: Color) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = explosiveness
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.18
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.scale_amount_min = scale_min
	particles.scale_amount_max = scale_max
	particles.color = color
	particles.emitting = false
	return particles


func _spark_mesh(color: Color, additive := true) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = color
	material.albedo_texture = _spark_texture()
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	return mesh


static var _spark_texture_cache: ImageTexture


func _spark_texture() -> ImageTexture:
	if _spark_texture_cache != null:
		return _spark_texture_cache
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	_spark_texture_cache = ImageTexture.create_from_image(image)
	return _spark_texture_cache


# ------------------------------------------------------------------ ground and screen

func _build_scorch() -> void:
	var scorch := MeshInstance3D.new()
	scorch.name = "Scorch"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.01
	disc.radial_segments = 32
	scorch.mesh = disc
	scorch.position = Vector3(0, 0.015, 0)
	var material := _glow_material(Color(0.1, 0.08, 0.06, 0.22), false)
	material.no_depth_test = false
	scorch.material_override = material
	add_child(scorch)
	var tween := create_tween()
	tween.tween_interval(SCORCH_LIFE)
	tween.tween_property(material, "albedo_color:a", 0.0, 2.0)


func _build_screen_flash(ui: CanvasLayer) -> void:
	if ui == null:
		return
	var flash := ColorRect.new()
	flash.name = "SkyFlash"
	flash.color = Color(0.72, 0.85, 1.0)
	flash.modulate = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(flash)
	ui.move_child(flash, 0)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.34, 0.02)
	tween.tween_property(flash, "modulate:a", 0.08, 0.09)
	tween.tween_property(flash, "modulate:a", 0.2, 0.035)
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


func _punch_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.fov = BASE_FOV
	var punch := create_tween()
	punch.tween_property(camera, "fov", 42.0, 0.06)
	punch.tween_property(camera, "fov", BASE_FOV, 0.35)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var shake := create_tween()
	for i in 6:
		shake.tween_property(camera, "h_offset", randf_range(-0.09, 0.09), 0.03)
		shake.parallel().tween_property(camera, "v_offset", randf_range(-0.06, 0.06), 0.03)
	shake.tween_property(camera, "h_offset", 0.0, 0.08)
	shake.parallel().tween_property(camera, "v_offset", 0.0, 0.08)


# ------------------------------------------------------------------ glow material

func _glow_material(color: Color, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
