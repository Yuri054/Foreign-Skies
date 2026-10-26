extends SceneTree
## Headless test of the cosmetic Storm mode: a strike spawns its 3D effect, changes no game state,
## the L key and a left click drive it, and a right click leaves it.
## Run: godot --headless --path . -s res://tests/lightning_test.gd

var _failures := 0
var gs: Node
var map: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _click(button: int, pressed: bool, at := Vector2(640, 360)) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://lightning_settings.cfg"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs = root.get_node("GameState")
	gs.ai_enabled = false
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	await process_frame
	map = get_first_node_in_group("map_3d")
	_check(map != null and not map.storm_mode, "the 3D map starts without its Storm mode")

	map.set_enabled(true)
	await process_frame
	await process_frame
	_check(map.enabled, "the 3D map is on")

	var log_before: int = gs.command_log.size()
	var owners_before: PackedStringArray = gs.province_owner.duplicate()
	var wars_before: int = gs.wars.size()
	var treasury_before: float = gs.nations["FRA"].treasury
	_check(map.strike_at(Vector2(640, 360)), "a strike at the centre of the screen is on the picture")
	_check(map._strikes.size() == 1 and is_instance_valid(map._strikes[0]), "one effect is alive")
	var effect: Node = map._strikes[0]
	_check(effect.get_node_or_null("Bolt") != null and effect.get_node_or_null("Flash") != null and effect.get_node_or_null("Scorch") != null, "it has a bolt, a flash and a scorch")
	_check(effect.get_node_or_null("Shockwave") != null and effect.get_node_or_null("Sparks") != null, "it has a shockwave and sparks")
	_check(gs.command_log.size() == log_before, "the strike issues no command")
	_check(gs.province_owner == owners_before, "and changes no province")
	_check(gs.wars.size() == wars_before, "nor starts a war")
	_check(is_equal_approx(gs.nations["FRA"].treasury, treasury_before), "nor spends a penny")

	map.clear_strikes()
	await process_frame
	_check(map._strikes.is_empty(), "the effects can be cleared")

	# L enters the mode; a left click in it calls a strike instead of selecting a province.
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	map._unhandled_key_input(key)
	_check(map.storm_mode, "L enters the Storm mode")
	var log_mode: int = gs.command_log.size()
	map._unhandled_input(_click(MOUSE_BUTTON_LEFT, true))
	_check(map._strikes.size() == 1, "a left click in the mode calls a strike")
	_check(gs.command_log.size() == log_mode, "and is not an order to an army")
	map._unhandled_input(_click(MOUSE_BUTTON_RIGHT, true))
	_check(not map.storm_mode, "a right click leaves the mode")

	# The palette has a Storm button, and it turns the 3D map on if that is off.
	var palette: Node = get_first_node_in_group("map_modes")
	_check(palette != null and palette._storm != null, "the map-mode palette has a Storm button")
	map.set_enabled(false)
	await process_frame
	await process_frame
	_check(not map.enabled, "the 3D map can be turned off")
	palette._storm.pressed.emit()
	await process_frame
	_check(map.enabled and map.storm_mode, "the Storm button turns the 3D map on with the mode")
	palette._storm.pressed.emit()
	_check(not map.storm_mode, "and pressing it again leaves the mode")

	map.clear_strikes()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lightning_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
