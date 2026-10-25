extends SceneTree
## Drives the goal picker through the main scene: Justify war opens it, it lists the target's
## provinces (the border first), a goal prices the case, Start begins the work, and the news feed
## and the peace screen show the goal.
## Run: godot --headless --path . -s res://tests/goal_picker_test.gd

var _failures := 0
var gs: Node
var main: Node
var G


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	G = load("res://scripts/sim/war_goal.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	gs.nations["GER"].diplomacy_points = 200.0
	await process_frame

	var panel: Node = get_first_node_in_group("diplomacy_panel")
	var picker: Node = get_first_node_in_group("goal_picker")
	_check(panel != null and picker != null, "the diplomacy panel and the goal picker exist")
	_check(not picker.visible, "the picker starts closed")
	panel.show_nation("BEL")
	await process_frame
	panel._on_justify()
	await process_frame
	_check(picker.visible, "Justify war opens the picker")
	_check(picker._start.disabled and picker.current_goal().is_empty(), "with nothing chosen, Start is off")
	_check(picker._province_ids.size() == gs.nations["BEL"].provinces.size(), "the target's provinces are listed")
	picker._provinces.select(0, false)
	picker._refresh()
	var goal: Dictionary = picker.current_goal()
	_check(goal.get("kind", "") == "provinces" and goal.ids.size() == 1, "ticking a province makes a province goal")
	_check(not picker._start.disabled and picker._info.text.contains("diplomacy points"), "Start is on and says what it costs: %s" % picker._info.text)
	picker._kind.select(1)
	picker._refresh()
	_check(picker._concession.visible and not picker._provinces.visible, "the concession choice swaps the list")
	_check(picker.current_goal().kind == "concession", "and gives a concession goal")
	picker._kind.select(0)
	picker._refresh()
	var news: Array = []
	gs.news_posted.connect(func(t: String, _l: int) -> void: news.append(t))
	picker._on_start()
	_check(not picker.visible and Diplomacy_justifying("GER", "BEL"), "Start begins the case and closes the picker")
	var work: Dictionary = gs.justifications[0]
	_check(work.goal.kind == "provinces", "the work holds the goal")

	# The peace screen shows the goal.
	gs.justifications.clear()
	gs.set_war("GER", "BEL", true, "fabricated_claim")
	var war: War = gs.war_between("GER", "BEL")
	war.goal = G.provinces_goal([gs.nations["BEL"].provinces[0]])
	var screen: Node = get_first_node_in_group("peace_screen")
	screen.open_war(war.id)
	await process_frame
	_check(screen._goal.visible and screen._goal.text.contains("fights"), "the peace screen states the goal: %s" % screen._goal.text)
	_check(not screen._goal_button.disabled, "and offers to select it")
	screen._goal_button.pressed.emit()
	_check(screen._provinces.get_selected_items().size() == 1, "which ticks the goal province")
	_check(screen._provinces.get_item_text(screen._province_ids.find(war.goal.ids[0])).contains("(goal)"), "marked in the list")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func Diplomacy_justifying(a: String, b: String) -> bool:
	return load("res://scripts/sim/diplomacy.gd").justifying(gs, a, b) != null
