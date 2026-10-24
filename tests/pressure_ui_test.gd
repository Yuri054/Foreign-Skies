extends SceneTree
## Windowed test of the event prompt and the tension display: an event concerning the player stops time and shows
## its options; answering one clears it; the top bar and the Overview show tension.
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/pressure_ui_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://pressure_ui_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.set_player("GER")
	gs.ai_enabled = false
	var prompt: Node = get_first_node_in_group("event_prompt")
	_check(prompt != null and not prompt.visible, "the event prompt is there and closed")
	while clock.year * 12 + clock.month < 1900 * 12 + 7:
		clock.advance_day()
	for i in 4:
		await process_frame
	_check(prompt.visible and prompt._decision.event == "boxer", "the Boxer Rising comes up")
	_check(prompt._options.get_child_count() == 2 and prompt._title.text == "The Boxer Rising", "with its two answers")
	var bar: Node = get_first_node_in_group("top_bar")
	_check(bar != null and bar._tension.text == str(roundi(gs.tension)) and bar._chips["tension"].tooltip_text.contains("tension"), "the top bar shows tension")
	prompt._answer(0)
	await process_frame
	_check(not prompt.visible and gs.pending_events.is_empty(), "answering clears it")
	get_first_node_in_group("nation_screen").open_page("Overview")
	await process_frame
	await process_frame
	var overview: Node = get_first_node_in_group("nation_screen").page_named("Overview")
	_check(_has_text(overview, "Tension") and _has_text(overview, "The Boxer Rising"), "the Overview shows tension and what has happened")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _has_text(node: Node, needle: String) -> bool:
	if "text" in node and str(node.text).contains(needle):
		return true
	for c in node.get_children():
		if _has_text(c, needle):
			return true
	return false
