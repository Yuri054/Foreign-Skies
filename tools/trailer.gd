extends SceneTree
## Renders the trailer from the game itself (Godot's movie writer: every frame is the game's own, at a fixed 30 a second, with its own
## music). A minute and a quarter: the menu, 1900 in time lapse, the briefing and the war goals, the great war on the map, the 3D map,
## the history book, the title. Needs a display (xvfb-run on a server) and ffmpeg to make an mp4 of the avi.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --write-movie trailer.avi --fixed-fps 30 -s res://tools/trailer.gd [-- quick]
##   ffmpeg -i trailer.avi -c:v libx264 -crf 22 -pix_fmt yuv420p -c:a aac -b:a 160k trailer.mp4
##
## With `quick` after `--` every beat lasts a moment: a check that the script runs.

const FPS := 30

var gs: Node
var clock: Node
var audio: Node
var map_data: Node
var main: Node
var quick := false
var _layer := CanvasLayer.new()
var _caption := Label.new()
var _fade := ColorRect.new()


func _s(seconds: float) -> int:
	return maxi(2, roundi(seconds * FPS * (0.08 if quick else 1.0)))


func _wait(frames: int) -> void:
	for i in frames:
		_clear_events()
		await process_frame


## The trailer is not played: whatever the game asks (an event, a crisis) is answered with its first option, out of sight.
func _clear_events() -> void:
	var pressure = load("res://scripts/sim/pressure.gd")
	for d: Dictionary in gs.pending_events.duplicate():
		pressure.answer(gs, d.id, 0)
	clock.paused = true


func _initialize() -> void:
	quick = OS.get_cmdline_user_args().has("quick")
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	audio = root.get_node("Audio")
	map_data = root.get_node("MapData")
	load("res://scripts/ui/ui_settings.gd").path = "user://trailer_settings.cfg"
	_layer.layer = 100
	root.add_child(_layer)
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	_caption.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.08))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -120.0
	_caption.offset_bottom = -50.0
	_caption.modulate.a = 0.0
	_layer.add_child(_caption)

	await _menu_beat()
	await _peace_beat()
	await _desk_beat()
	await _war_beat()
	await _view3d_beat()
	await _history_beat()
	await _title_beat()
	quit(0)


# --- Helpers ---------------------------------------------------------------------------------

func _fade_to(alpha: float, seconds: float) -> void:
	var frames := _s(seconds)
	var from := _fade.color.a
	for i in frames:
		_fade.color.a = lerpf(from, alpha, float(i + 1) / frames)
		await process_frame


## A caption fades in, stays, fades out: `seconds` in all. Runs beside the beat (call without await).
func _say(text: String, seconds: float) -> void:
	_caption.text = text
	var frames := _s(seconds)
	var fade := mini(10, frames / 4)
	for i in frames:
		_caption.modulate.a = clampf(minf(float(i) / fade, float(frames - i) / fade), 0.0, 1.0)
		await process_frame
	_caption.modulate.a = 0.0


func _start(scenario: String, player: String, ai: bool) -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	gs.difficulty = "historical"
	gs.load_scenario(scenario)
	gs.ai_seed = 7
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.set_player(player)
	gs.ai_enabled = ai
	if player == "":
		gs.player_tag = ""
	clock.paused = true
	audio.set_music_context("game")


func _days(n: int, per_frame: int, camera_to := Vector2.ZERO, zoom_to := 0.0) -> void:
	var cam: Camera2D = main.camera
	var p0 := cam.position
	var z0 := cam.zoom.x
	var frames := ceili(float(n) / per_frame)
	for i in frames:
		for k in per_frame:
			clock.advance_day()
		_clear_events()
		if zoom_to > 0.0:
			var t := smoothstep(0.0, 1.0, float(i + 1) / frames)
			cam.position = p0.lerp(camera_to, t)
			var z := lerpf(z0, zoom_to, t)
			cam.zoom = Vector2(z, z)
		await process_frame


func _glide(to: Vector2, zoom_to: float, frames: int) -> void:
	var cam: Camera2D = main.camera
	var p0 := cam.position
	var z0 := cam.zoom.x
	for i in frames:
		var t := smoothstep(0.0, 1.0, float(i + 1) / frames)
		cam.position = p0.lerp(to, t)
		var z := lerpf(z0, zoom_to, t)
		cam.zoom = Vector2(z, z)
		await process_frame


func _center(province_name: String) -> Vector2:
	for id in range(1, map_data.provinces.size()):
		if map_data.provinces[id].name == province_name:
			return map_data.provinces[id].center
	return Vector2(2400, 2500)


# --- The beats ---------------------------------------------------------------------------------

func _menu_beat() -> void:
	audio.set_music_context("menu")
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await _wait(2)
	_say("FOREIGN SKIES", 4.5)
	await _fade_to(0.0, 1.2)
	await _wait(_s(4.5))
	await _fade_to(1.0, 1.0)
	menu.queue_free()
	await process_frame


func _peace_beat() -> void:
	await _start("res://data/scenarios/jan_1900/", "GER", false)
	var cam: Camera2D = main.camera
	cam.zoom = Vector2(0.2, 0.2)
	cam.position = Vector2(3300, 2700)
	await _wait(2)
	_say("January 1900. Europe is at peace.", 5.0)
	_fade_to(0.0, 1.0)
	await _days(150, 3, Vector2(3000, 2600), 0.34)
	_say("Twenty-two nations. One continent. Fourteen years.", 4.5)
	await _days(180, 3, Vector2(2700, 2700), 0.5)


func _desk_beat() -> void:
	var screen: Node = get_first_node_in_group("nation_screen")
	var overview: Node = get_first_node_in_group("overview_panel")
	gs.tension_history.assign([21.0, 22.0, 24.0, 25.0, 27.0, 31.0, 34.0, 38.0, 42.0, 47.0, 52.0, 58.0])
	_say("Run a nation.", 3.0)
	screen.open_page(overview)
	await _wait(_s(3.2))
	_say("Read the briefing. Spend your points.", 3.0)
	screen.open_page("Diplomacy")
	var panel: Node = get_first_node_in_group("diplomacy_panel")
	panel.show_nation("FRA")
	await _wait(_s(3.2))
	screen.close_screen()
	var picker: Node = get_first_node_in_group("goal_picker")
	gs.nations["GER"].diplomacy_points = 120.0
	panel.show_nation("BEL")
	picker.open("BEL")
	picker._provinces.select(0, false)
	picker._provinces.select(1, false)
	picker._refresh()
	_say("Choose what you fight for.", 3.4)
	await _wait(_s(3.6))
	picker.visible = false
	await _fade_to(1.0, 0.8)


func _war_beat() -> void:
	await _start("res://data/scenarios/july_1914/", "", true)
	var cam: Camera2D = main.camera
	cam.zoom = Vector2(0.3, 0.3)
	cam.position = Vector2(2300, 2500)
	main.map_view.set_mode(main.map_view.Mode.MILITARY, main.map_view.MIL_FRONT)
	audio.set_music_context("game")
	await _wait(2)
	_say("July 1914. The alliances are drawn.", 4.0)
	_fade_to(0.0, 0.8)
	await _days(60, 2, Vector2(2250, 2550), 0.42)
	_say("A shot in Sarajevo. Europe marches.", 4.0)
	await _days(100, 2, Vector2(2050, 2650), 0.7)
	main.map_view.set_mode(main.map_view.Mode.POLITICAL)
	_say("Every front, every battle, every peace.", 4.0)
	await _days(120, 2, Vector2(2650, 2200), 0.55)
	await _days(100, 2, Vector2(3300, 2450), 0.45)


func _view3d_beat() -> void:
	var m3: Node = get_first_node_in_group("map_3d")
	var cam: Camera2D = main.camera
	m3.set_enabled(true)
	m3.tilt = 58.0
	m3._apply_tilt()
	cam.position = Vector2(2100, 2650)
	cam.zoom = Vector2(0.9, 0.9)
	await _wait(3)
	_say("Or watch it unfold in three dimensions.", 4.5)
	await _days(60, 1, Vector2(2200, 2600), 1.35)
	await _days(40, 1, Vector2(2000, 2700), 1.6)
	m3.set_enabled(false)


func _history_beat() -> void:
	var screen: Node = get_first_node_in_group("nation_screen")
	var book: Node = get_first_node_in_group("history_book")
	gs.set_player("FRA")
	screen.open_page(book)
	book._tabs.current_tab = 0
	await _wait(2)
	_say("Everything that happens is written into history.", 5.0)
	await _wait(_s(2.6))
	book._tabs.current_tab = 2
	await _wait(_s(2.6))
	screen.close_screen()


func _title_beat() -> void:
	await _fade_to(1.0, 1.0)
	_say("FOREIGN SKIES", 6.0)
	await _wait(_s(2.0))
	_caption.text = "FOREIGN SKIES\nA sandbox of Europe, 1900 to the great war"
	await _wait(_s(4.0))
	await _fade_to(1.0, 0.2)
