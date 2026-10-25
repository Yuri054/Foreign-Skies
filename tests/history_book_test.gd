extends SceneTree
## Headless test for the history book: the logs fill as the run goes (events, wars, peaces, crises, treaties, every change
## of owner, a row of figures a month), the sections are built from them, the exports are whole, a save keeps the record,
## and the page of the Nation screen shows it all.
## Run: godot --headless --path . -s res://tests/history_book_test.gd

var _failures := 0
var gs: Node
var clock: Node
var H
var main: Node


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
	clock = root.get_node("Clock")
	H = load("res://scripts/sim/history.gd")
	var Peace = load("res://scripts/sim/peace.gd")
	var D = load("res://scripts/sim/diplomacy.gd")

	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.set_player("ESP")
	gs.ai_enabled = false
	gs.wars.clear()
	_check(gs.history_log.is_empty() and gs.territory_log.is_empty() and gs.history_months.is_empty(), "a new run has an empty record")

	# A war, a battle, a peace with a province, a treaty.
	gs.set_war("GER", "BEL", true, "none")
	_check(not H.timeline(gs, 0, ["war"]).is_empty() and H.timeline(gs, 0, ["war"])[0].text.contains("declares war"), "a declaration is written down")
	var war = gs.war_between("GER", "BEL")
	war.add_battle({"id": 1, "name": "Liege", "date": "5 May 1900", "days": 3, "attacker": "GER", "winner": "GER", "strength": {"GER": 9000.0, "BEL": 4000.0}, "lost": 1200.0, "province": 1})
	war.losses["BEL"] = 2500.0
	var province: int = gs.nations["BEL"].provinces[0]
	gs.province_controller[province] = "GER"
	var offer := {"taker": "GER", "giver": "BEL", "demands": [{"kind": "province", "ids": [province]}], "cost": 5.0, "forced": true, "note": ""}
	Peace.make_peace(gs, war, offer)
	_check(gs.territory_log.size() == 1 and gs.territory_log[0].new == "GER" and gs.territory_log[0].old == "BEL", "a change of owner is logged")
	var peaces: Array = H.timeline(gs, 0, ["peace"])
	_check(peaces.size() == 1 and peaces[0].text.contains("takes"), "the peace is told with its terms: %s" % peaces[0].text)
	D.add_treaty(gs, "alliance", "ESP", "POR")
	_check(H.timeline(gs, 0, ["treaty"]).any(func(e: Dictionary) -> bool: return e.text.contains("Alliance")), "an alliance is written down")
	gs.nations["GER"].diplomacy_points = 100.0

	# Months.
	for i in 40:
		clock.advance_day()
	for i in 35:
		clock.advance_day()
	_check(gs.history_months.size() >= 2, "a row of figures is kept each month (%d)" % gs.history_months.size())
	var row: Dictionary = gs.history_months[gs.history_months.size() - 1]
	_check(row.has("tension") and row.has("wars") and row.has("casualties") and row.top.size() == 3, "a row has the tension, the wars, the losses and the top three")
	_check(H.headline(gs, row.year, row.month) != "", "every month has a headline: %s" % H.headline(gs, row.year, row.month))
	_check(H.year_summary(gs, 1900).begins_with("1900:"), "a year has its summary: %s" % H.year_summary(gs, 1900))

	# Sections.
	var wars: Array = H.wars_section(gs)
	_check(wars.size() == 1 and "Liege" in "\n".join(wars[0].lines), "the wars section tells the war and its battle")
	_check(H.territory_lines(gs).size() == 1 and H.territory_lines(gs, 1900).size() == 1 and H.territory_lines(gs, 1950).is_empty(), "the territory lines can be had for a year")
	var nations: Array = H.nations_section(gs)
	_check(nations.size() > 5 and nations[0].has("d_industry"), "the nations section ranks the nations against the start")
	var image: Image = H.map_image(gs, 32)
	_check(image.get_width() > 100 and image.get_height() > 50, "the map picture is made (%dx%d)" % [image.get_width(), image.get_height()])
	var md: String = H.markdown(gs)
	_check(md.contains("# Europe, 1900") and md.contains("## 1900") and md.contains("## The wars") and md.contains("| Nation |"), "the Markdown has its parts")
	var html: String = H.html(gs, false)
	_check(html.begins_with("<!doctype html>") and html.contains("<h2>") and html.contains("<table>") and html.ends_with("</html>"), "the HTML page is whole")
	var path: String = H.export(gs, "md")
	_check(path != "" and FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == md, "the Markdown file is written and matches")
	var path_html: String = H.export(gs, "html")
	_check(path_html != "" and FileAccess.get_file_as_string(path_html).contains("data:image/png;base64,"), "the HTML file carries the map")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_html))

	# The caps hold.
	var before: int = gs.history_log.size()
	for i in H.LOG_MAX + 10:
		H.note(gs, "event", "x")
	_check(gs.history_log.size() == H.LOG_MAX and before < H.LOG_MAX, "the log is capped at %d" % H.LOG_MAX)

	# A save keeps the record.
	var SaveGame = load("res://scripts/sim/save_game.gd")
	var spath := "user://history_book_test.sav"
	var logs: int = gs.history_log.size()
	var terr: int = gs.territory_log.size()
	var months: int = gs.history_months.size()
	SaveGame.write(gs, spath)
	gs.history_log.clear()
	gs.territory_log.clear()
	gs.history_months.clear()
	SaveGame.read(gs, spath)
	_check(gs.history_log.size() == logs and gs.territory_log.size() == terr and gs.history_months.size() == months, "a saved and loaded game keeps its record")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(spath))

	# The page.
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.set_player("ESP")
	var screen: Node = get_first_node_in_group("nation_screen")
	var book: Node = get_first_node_in_group("history_book")
	_check(book != null and screen.page_named("History") == book, "the history book is a page of the Nation screen")
	screen.open_page(book)
	await process_frame
	await process_frame
	_check(book._year.item_count >= 1 and book._timeline.get_child_count() >= 1, "its timeline lists the year")
	book._tabs.current_tab = 1
	await process_frame
	_check(book._wars.get_child_count() >= 1, "the wars tab fills")
	book._tabs.current_tab = 2
	await process_frame
	_check(book._map_picture.texture != null, "the map tab shows the picture")
	book._tabs.current_tab = 3
	await process_frame
	_check(book._nations.get_child_count() > 8, "the nations tab fills")
	book._tabs.current_tab = 4
	book._copy()
	# (A headless display has no clipboard to read back.)
	_check(DisplayServer.get_name() == "headless" or DisplayServer.clipboard_get().contains("# Europe"), "Copy puts the book on the clipboard")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
