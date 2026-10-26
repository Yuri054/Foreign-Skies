class_name Lightning
extends Node3D
## A cosmetic lightning strike on the 3D map: a jagged, branching ribbon from the sky to the ground,
## a short blue-white flash, and a scorch that fades. It is pure spectacle: it reads and writes no
## game state. One node per strike; it frees itself after the effect is over.
##
## `strike(parent, ground, camera, ui)` adds one to `parent` at `ground` (a point on the 3D map).
## The map's plane is only 16 by 9 units, so the bolt is a few units tall rather than world-scale.

const BOLT_HEIGHT := 3.6
const BOLT_WIDTH := 0.045
const BOLT_STEPS := 11
const BOLT_LIFE := 0.5
const SCORCH_LIFE := 3.2
const TOTAL_LIFE := 5.2

const CORE_COLOR := Color(0.86, 0.93, 1.0)
const GLOW_COLOR := Color(0.45, 0.68, 1.0)


static func strike(parent: Node3D, ground: Vector3, camera: Camera3D, ui: CanvasLayer = null) -> Node3D:
	var effect := Lightning.new()
	effect.position = ground
	parent.add_child(effect)
	effect._build(camera, ui)
	return effect


func _build(camera: Camera3D, ui: CanvasLayer) -> void:
	_build_bolt(camera)
	_build_flash()
	_build_scorch()
	_build_screen_flash(ui)
	get_tree().create_timer(TOTAL_LIFE).timeout.connect(queue_free)


## The bolt: one ImmediateMesh of camera-facing ribbon segments, with one or two short branches.
func _build_bolt(camera: Camera3D) -> void:
	var points: Array[Vector3] = []
	var top := Vector3(randf_range(-0.5, 0.5), BOLT_HEIGHT, randf_range(-0.5, 0.5))
	for i in BOLT_STEPS + 1:
		var t := float(i) / float(BOLT_STEPS)
		var p := top.lerp(Vector3.ZERO, t)
		var spread := lerpf(0.28, 0.07, t)
		p.x += randf_range(-spread, spread)
		p.z += randf_range(-spread, spread)
		p.y += randf_range(-0.06, 0.06)
		points.append(p)

	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = CORE_COLOR
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = 5.0
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	_add_segments(mesh, points, camera, BOLT_WIDTH)
	# Two short branches off the lower half, so the bolt reads as lightning rather than a zigzag.
	for start in [maxi(1, BOLT_STEPS / 3), maxi(1, (BOLT_STEPS * 2) / 3)]:
		var branch: Array[Vector3] = [points[start]]
		for i in 3:
			var p: Vector3 = branch[i]
			p += Vector3(randf_range(-0.4, 0.4), -randf_range(0.18, 0.36), randf_range(-0.4, 0.4))
			branch.append(p)
		_add_segments(mesh, branch, camera, BOLT_WIDTH * 0.55)
	mesh.surface_end()

	var bolt := MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.mesh = mesh
	add_child(bolt)
	var tween := create_tween()
	# A few stutters, then fade the material out.
	tween.tween_interval(0.04)
	tween.tween_callback(func() -> void: bolt.visible = false)
	tween.tween_interval(0.035)
	tween.tween_callback(func() -> void: bolt.visible = true)
	tween.tween_interval(0.05)
	tween.tween_callback(func() -> void: bolt.visible = false)
	tween.tween_interval(0.04)
	tween.tween_callback(func() -> void: bolt.visible = true)
	tween.tween_property(material, "albedo_color:a", 0.0, BOLT_LIFE - 0.16)


## Adds a ribbon of camera-facing quads following `points`.
func _add_segments(mesh: ImmediateMesh, points: Array[Vector3], camera: Camera3D, width: float) -> void:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var mid := (a + b) * 0.5
		var view := camera.global_position - (global_position + mid) if camera != null else Vector3(0, 0, 1)
		var side := (b - a).cross(view)
		if side.length_squared() < 0.000001:
			continue
		side = side.normalized() * width
		var a1 := a - side
		var a2 := a + side
		var b1 := b - side
		var b2 := b + side
		for v in [a1, b1, b2, a1, b2, a2]:
			mesh.surface_add_vertex(v)


## The light the bolt casts on the ground.
func _build_flash() -> void:
	var light := OmniLight3D.new()
	light.name = "Flash"
	light.position = Vector3(0, 1.1, 0)
	light.light_color = Color(0.72, 0.84, 1.0)
	light.light_energy = 9.0
	light.omni_range = 5.0
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.3)


## A dark mark where the bolt meets the ground. A flat quad rather than a Decal: the game runs on
## the GL Compatibility renderer, where decals are not available.
func _build_scorch() -> void:
	var scorch := MeshInstance3D.new()
	scorch.name = "Scorch"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 1.3)
	scorch.mesh = plane
	scorch.position = Vector3(0, 0.02, 0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.04, 0.03, 0.02, 0.9)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.95), Color(0, 0, 0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	material.albedo_texture = texture
	scorch.material_override = material
	add_child(scorch)
	var tween := create_tween()
	tween.tween_interval(SCORCH_LIFE)
	tween.tween_property(material, "albedo_color:a", 0.0, 1.4)


## A brief white-blue wash over the map, behind the interface windows.
func _build_screen_flash(ui: CanvasLayer) -> void:
	if ui == null:
		return
	var flash := ColorRect.new()
	flash.name = "SkyFlash"
	flash.color = Color(0.78, 0.88, 1.0)
	flash.modulate = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(flash)
	ui.move_child(flash, 0)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.38, 0.035)
	tween.tween_property(flash, "modulate:a", 0.0, 0.22)
	tween.tween_callback(flash.queue_free)
