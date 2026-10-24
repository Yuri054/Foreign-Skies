extends SceneTree
## Headless test for the rankings: the figures and their order, the monthly history, and the
## Rankings window with its chart, table and trend.
## Run: godot --headless --path . -s res://tests/rankings_test.gd

var _failures := 0
var main: Node
var gs: Node
var clock: Node
var S


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	S = load("res://scripts/sim/standings.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame

	_test_standings()
	await _test_history()
	await _test_window()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_standings() -> void:
	var ids: PackedStringArray = []
	for m: Dictionary in S.METRICS:
		ids.append(m.id)
	_check(ids.size() == 12 and "navy" in ids and "diplomacy_points" in ids and "population" in ids and "treasury" in ids and "war_support" in ids, "twelve figures can be ranked (%s)" % ", ".join(ids))
	var pop: Array = S.ranking(gs, "population")
	_check(pop.size() == 22, "every nation with land is ranked (%d)" % pop.size())
	var sorted := true
	for i in range(1, pop.size()):
		if pop[i].value > pop[i - 1].value:
			sorted = false
	_check(sorted and pop[0].tag == "RUS", "best first, Russia the most populous (%s)" % pop[0].tag)
	_check(S.rank_of(gs, "RUS", "population") == 1 and S.rank_of(gs, "FRA", "population") > 1, "rank_of agrees")
	_check(S.rank_of(gs, "XXX", "population") == 0, "and is 0 for a stranger")
	_check(is_equal_approx(S.value(gs, "FRA", "gdp"), gs.nations["FRA"].budget.gdp / 12.0), "output is a monthly figure")
	_check(S.value(gs, "GER", "provinces") == gs.nations["GER"].provinces.size(), "provinces are a count")
	gs.nations["GER"].treasury = -40.0
	var treasuries: Array = S.ranking(gs, "treasury")
	_check(treasuries.back().tag == "GER" and treasuries.back().value == -40.0, "a nation in debt ranks last in treasury")
	gs.nations["GER"].treasury = 45.0
	# A nation without land is left out.
	var luxembourg: Array = gs.nations["LUX"].provinces.duplicate()
	_check(S.ranking(gs, "army").size() == 22, "armies are ranked for every nation")


func _test_history() -> void:
	_check(gs.standings_history.size() == 1 and gs.standings_history[0].values.has("FRA"), "the history starts with a record of the first day")
	_check(gs.standings_history[0].values.FRA.has("army") and gs.standings_history[0].date == "28 July 1914", "with every figure and the date")
	for i in 95:
		clock.advance_day()
	_check(gs.standings_history.size() == 4, "a record is added each month (%d after three months)" % gs.standings_history.size())
	var series: Array = S.series(gs, "FRA", "population")
	_check(series.size() == 4 and series[0].x == 0 and series[3].x == 3, "series gives one point a record")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	_check(gs.standings_history.size() == 1, "loading a scenario starts the history again")
	for i in 3:
		clock.advance_day()
	for i in S.MAX_MONTHS + 5:
		S.record(gs)
	_check(gs.standings_history.size() == S.MAX_MONTHS, "and it is capped at %d months" % S.MAX_MONTHS)
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame


func _key(win: Node, code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	win._unhandled_key_input(e)


func _test_window() -> void:
	var win: Node = get_first_node_in_group("rankings_window")
	_check(win != null and win.has_method("setup_window"), "the rankings window exists and is a window")
	_key(win, KEY_R)
	await process_frame
	await process_frame
	var screen: Node = get_first_node_in_group("nation_screen")
	_check(win.visible and win.host == screen and screen.current_page() == win, "R opens it as a page of the Nation screen")
	_check(win._table.get_child_count() > 0 and win._trend != null, "it has a table and a trend on one page")
	_check(win._summary.text.contains("Population") and win._summary.text.contains("you are #") and win._summary.text.contains("Russian Empire leads"), "the summary says where you stand and who leads (%s)" % win._summary.text)
	win.show_metric("army")
	await process_frame
	await process_frame
	_check(win._summary.text.contains("Army:") and win._picker.get_item_text(win._picker.selected) == "Army", "choosing another figure re-ranks")
	var stats: Node = get_first_node_in_group("nation_stats")
	stats.close_window()
	win._show_nation("ITA")
	_check(stats.visible and stats.shown_tag() == "ITA", "clicking a nation shows it in the country panel")
	stats.close_window()

	# Table.
	await process_frame
	await process_frame
	_check(win._table.get_child_count() == (2 + win.TABLE_COLUMNS.size()) * 23, "the table has a heading row and a row per nation (%d cells)" % win._table.get_child_count())
	var heading: Button = win._table.get_child(2 + win.TABLE_COLUMNS.find("gdp"))
	heading.pressed.emit()
	await process_frame
	await process_frame
	_check(win._sort == "gdp", "clicking a heading sorts by it")
	var sorted_heading: Button = win._table.get_child(2 + win.TABLE_COLUMNS.find("gdp"))
	_check(sorted_heading.text.contains("▾"), "and marks the column")

	# Trend.
	await process_frame
	await process_frame
	_check(win._trend.message != "", "the trend asks for a little time to pass at first (%s)" % win._trend.message)
	for i in 95:
		root.get_node("Clock").advance_day()
	await process_frame
	await process_frame
	win._refresh()
	_check(win._trend.message == "" and win._trend.series.size() >= 5, "after some months it charts the leaders (%d lines)" % win._trend.series.size())
	var bold := 0
	for s in win._trend.series:
		if s.bold:
			bold += 1
	_check(bold == 1, "and your own nation in bold")
	_check(win._trend.series[0].points.size() == 4 and win._trend.x_labels[0] == "28 July 1914", "from the first day (%s)" % win._trend.x_labels[1])
	win.close_window()
	_check(not win.visible and not screen.visible, "the X closes the screen")
