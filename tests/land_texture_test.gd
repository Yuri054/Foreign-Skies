extends SceneTree
## Headless test for the land texture: the blend grows as the camera zooms in, it shows under the
## nations' colours but not under data maps, it can be switched off, and the 3D map asks for more.
## Run: godot --headless --path . -s res://tests/land_texture_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var MV = load("res://scripts/map/map_view.gd")
	_check(MV.land_blend_for(0.2) < MV.land_blend_for(0.6) and MV.land_blend_for(0.6) < MV.land_blend_for(1.5), "the texture shows more the closer the camera is")
	_check(is_equal_approx(MV.land_blend_for(0.1), MV.LAND_BLEND_FAR) and is_equal_approx(MV.land_blend_for(5.0), MV.LAND_BLEND_NEAR), "between a floor and a ceiling")
	_check(MV.land_natural_for(0.3) < MV.land_natural_for(1.5), "and so does the ground's own colour")
	var tex: Texture2D = load("res://data/map/land.jpg")
	_check(tex != null and tex.get_width() >= 2000, "the land texture is there (%dx%d)" % [tex.get_width(), tex.get_height()])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var view = main.map_view
	var mat: ShaderMaterial = view._material
	_check(mat.get_shader_parameter("land_texture") != null, "the map shader has the texture")
	view.set_mode(MV.Mode.POLITICAL)
	_check(mat.get_shader_parameter("land_on"), "it shows under the political colours")
	view.set_mode(MV.Mode.INCOME)
	_check(not mat.get_shader_parameter("land_on"), "but not under a data map")
	view.set_mode(MV.Mode.POLITICAL)
	view.land_texture_enabled = false
	_check(not mat.get_shader_parameter("land_on"), "it can be switched off")
	view.land_texture_enabled = true
	main.camera.zoom = Vector2(0.3, 0.3)
	await process_frame
	await process_frame
	var far: float = mat.get_shader_parameter("land_blend")
	view.land_zoom_floor = 0.9
	await process_frame
	await process_frame
	_check(mat.get_shader_parameter("land_blend") > far, "asking for a closer view (the 3D map does) shows more of it (%.2f to %.2f)" % [far, mat.get_shader_parameter("land_blend")])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
