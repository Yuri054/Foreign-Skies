extends SceneTree
## A named showcase picture of the game, for showing it to people:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --rendering-driver opengl3 \
##       -s res://tools/screenshot_showcase.gd -- NAME out.png
## NAME: menu, europe, war, front3d, diplomacy, supply, briefing, goals, history, battle, crisis.
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://showcase_settings.cfg"
	load("res://scripts/sim/save_game.gd").dir = "user://showcase_saves/"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var map_data: Node = root.get_node("MapData")
	var G = load("res://scripts/sim/war_goal.gd")
	var C = load("res://scripts/sim/crisis.gd")
	var a := OS.get_cmdline_user_args()
	var name: String = a[0]
	var out: String = a[1]
	if name == "menu":
		var menu: Node = load("res://scenes/menu.tscn").instantiate()
		root.add_child(menu)
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out)
		quit(0)
		return
	var war := name in ["war", "front3d", "supply", "battle"]
	gs.difficulty = "historical"
	gs.load_scenario("res://data/scenarios/july_1914/" if war else "res://data/scenarios/jan_1900/")
	gs.ai_seed = 7
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	var player := "GER"
	gs.set_player(player)
	gs.ai_enabled = true
	var cam: Camera2D = main.camera
	var view: Node = main.map_view
	var screen: Node = get_first_node_in_group("nation_screen")
	var pressure = load("res://scripts/sim/pressure.gd")
	clock.paused = true
	# Whatever the game asks while time passes is answered out of sight (a crisis is refused, an event takes its first option).
	var days := func(n: int) -> void:
		for i in n:
			clock.advance_day()
			if i % 3 == 0:
				for d: Dictionary in gs.pending_events.duplicate():
					pressure.answer(gs, d.id, 1 if str(d.event).begins_with("crisis:") else 0)
	match name:
		"europe":
			await days.call(200)
			cam.position = Vector2(3000, 2600)
			cam.zoom = Vector2(0.27, 0.27)
		"war":
			gs.player_tag = ""
			await days.call(230)
			view.set_mode(view.Mode.MILITARY, view.MIL_FRONT)
			cam.position = Vector2(2250, 2550)
			cam.zoom = Vector2(0.5, 0.5)
		"front3d":
			gs.player_tag = ""
			await days.call(230)
			cam.position = Vector2(2100, 2650)
			cam.zoom = Vector2(1.5, 1.5)
			get_first_node_in_group("map_3d").set_enabled(true)
			get_first_node_in_group("map_3d").tilt = 58.0
			get_first_node_in_group("map_3d")._apply_tilt()
		"supply":
			gs.player_tag = ""
			await days.call(150)
			gs.player_tag = "GER"
			gs.ai_enabled = true
			view.set_mode(view.Mode.MILITARY, view.MIL_SUPPLY)
			cam.position = Vector2(2900, 2450)
			cam.zoom = Vector2(0.4, 0.4)
		"diplomacy":
			await days.call(120)
			view.set_mode(view.Mode.DIPLOMACY)
			cam.position = Vector2(2900, 2500)
			cam.zoom = Vector2(0.34, 0.34)
		"briefing":
			await days.call(240)
			cam.position = Vector2(2900, 2500)
			cam.zoom = Vector2(0.4, 0.4)
			screen.open_page(get_first_node_in_group("overview_panel"))
		"goals":
			await days.call(60)
			gs.nations["GER"].diplomacy_points = 120.0
			cam.position = Vector2(2400, 2600)
			cam.zoom = Vector2(0.5, 0.5)
			screen.open_page("Diplomacy")
			get_first_node_in_group("diplomacy_panel").show_nation("BEL")
			var picker: Node = get_first_node_in_group("goal_picker")
			picker.open("BEL")
			picker._provinces.select(0, false)
			picker._provinces.select(1, false)
			picker._refresh()
		"history":
			await days.call(400)
			cam.position = Vector2(2900, 2500)
			cam.zoom = Vector2(0.4, 0.4)
			screen.open_page(get_first_node_in_group("history_book"))
			get_first_node_in_group("history_book")._tabs.current_tab = 0
		"battle":
			gs.player_tag = ""
			var best := 0
			var tries := 0
			while best == 0 and tries < 60:
				await days.call(10)
				tries += 1
				var most := 0.0
				for p: int in gs.engagements:
					var men := 0.0
					for side: Dictionary in gs.engagements[p].sides.values():
						men += side.men_now
					if men > most:
						most = men
						best = p
			gs.player_tag = "GER"
			if best > 0:
				cam.position = map_data.provinces[best].center
				cam.zoom = Vector2(0.9, 0.9)
				get_first_node_in_group("battle_screen").open_battle(gs.engagements[best].id)
		"crisis":
			await days.call(150)
			cam.position = Vector2(2800, 2500)
			cam.zoom = Vector2(0.4, 0.4)
			C.open(gs, {"a": "FRA", "b": "GER", "score": 1.0})
			await process_frame
	for i in 14:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit(0)
