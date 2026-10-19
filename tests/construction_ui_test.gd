extends SceneTree
## Headless test of the Construction panel: a top bar button opens it on the left, picking a
## building puts the map in Construction mode and colours provinces by where it stands and where it
## can be built, a click on a green province queues it, Ctrl-click retools a factory, hover says
## why not, mass building previews, and closing puts the map back.
## Run: godot --headless --path . -s res://tests/construction_ui_test.gd

var _failures := 0
var gs: Node
var main: Node
var panel: Control
var map_view: Sprite2D
var MapView
var Eco


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	MapView = load("res://scripts/map/map_view.gd")
	Eco = load("res://scripts/sim/economy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.pending_joins.clear()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	panel = get_first_node_in_group("construction_panel")
	map_view = main.get_node("MapView")
	await _test_open_and_colours()
	await _test_clicks()
	_test_retool_and_hover()
	await _test_close_and_mass()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _ger() -> Object:
	return gs.nations["GER"]


func _test_open_and_colours() -> void:
	_check(panel != null and panel.has_method("setup_window") and not panel.visible, "the Construction panel exists and starts closed")
	var bar: Node = main.get_node("UI/TopBar")
	_check(bar._window_buttons.has("construction_panel"), "the top bar has a button for it")
	bar._window_buttons["construction_panel"].pressed.emit()
	await process_frame
	_check(panel.visible, "the top bar button opens it")
	var legend_zone := Rect2(0, root.get_visible_rect().size.y - 140.0, 620, 140)
	_check(not panel.get_global_rect().intersects(legend_zone), "and it stays clear of the map legend and palette at the bottom left")
	_check(map_view.mode == MapView.Mode.CONSTRUCTION and map_view.submode == "factory", "the map shows where a civilian factory can be built")
	_check(panel.picked() == "factory" and panel._rows["factory"].button_pressed, "the first building is picked and lit")
	var eco_panel: Node = get_first_node_in_group("economy_panel")
	_check(eco_panel._tabs.get_tab_count() == 3 and eco_panel._tabs.get_tab_title(2) == "Production", "the Economy window has no Buildings tab, only Overview, Resources and Production")

	var free := 0
	var full := 0
	for id in _ger().provinces:
		if Eco.build_problem(gs, "GER", id, "factory", false).is_empty() and free == 0:
			free = id
		elif not Eco.build_problem(gs, "GER", id, "factory", false).is_empty() and full == 0:
			full = id
	var foreign: int = gs.nations["FRA"].provinces[0]
	_check(free > 0 and map_view.construction_color(free, "factory") in [MapView.CONSTRUCT_BUILD, MapView.CONSTRUCT_BOTH], "a province with room is green (or teal if it has some)")
	_check(map_view.construction_color(foreign, "factory") == MapView.CONSTRUCT_OTHER, "foreign land is dark")
	var cap: int = _ger().capital
	gs.province_slots[cap] = Eco.slots_used(gs, cap)
	gs.economy_updated.emit()
	var c: Color = map_view.construction_color(cap, "factory")
	_check(c != MapView.CONSTRUCT_BUILD and c != MapView.CONSTRUCT_BOTH, "a province with no free slot is no longer green")
	var with_factory := 0
	for id in _ger().provinces:
		if gs.province_buildings[id].get("factory", 0) > 0:
			with_factory = id
			break
	_check(map_view.construction_color(with_factory, "factory") in [MapView.CONSTRUCT_BOTH, MapView.CONSTRUCT_HAVE] or with_factory == cap, "a province with factories is blue or teal")
	panel._rows["port"].pressed.emit()
	await process_frame
	_check(map_view.submode == "port" and panel.picked() == "port", "picking the port shows the port map")
	var inland := 0
	for id in _ger().provinces:
		if not root.get_node("MapData").provinces[id].coastal:
			inland = id
			break
	_check(map_view.construction_color(inland, "port") == MapView.CONSTRUCT_BLOCKED, "an inland province is grey for a port")
	_check("coastal" in panel.status_of(inland), "and hovering says why: " + panel.status_of(inland))
	var lg: Dictionary = map_view.legend()
	_check(lg.has("title") and "port" in lg.title.to_lower(), "the legend names the building")
	_check(panel._rows["factory"].text.contains("built"), "each row counts what is built: " + panel._rows["factory"].text)


func _test_clicks() -> void:
	panel._rows["factory"].pressed.emit()
	await process_frame
	var ger = _ger()
	ger.treasury = 5000.0
	ger.stock.iron = 1e6
	ger.stock.coal = 1e6
	var id := 0
	for p in ger.provinces:
		if p != ger.capital and Eco.build_problem(gs, "GER", p, "factory").is_empty():
			id = p
			break
	var jobs: int = ger.construction.size()
	var cash: float = ger.treasury
	map_view.select(id)
	_check(ger.construction.size() == jobs + 1 and is_equal_approx(ger.treasury, cash), "a click on a green province queues a factory, which costs no money")
	_check(panel._status.text.contains("IC"), "and says what it cost: " + panel._status.text)
	# A province that cannot take it.
	var blocked: int = ger.capital
	gs.province_slots[blocked] = Eco.slots_used(gs, blocked)
	jobs = ger.construction.size()
	map_view.select(blocked)
	_check(ger.construction.size() == jobs and panel._status.text.contains("slot"), "a click where it cannot be built builds nothing and says why: " + panel._status.text)
	var foreign: int = gs.nations["FRA"].provinces[0]
	map_view.select(foreign)
	_check(ger.construction.size() == jobs, "foreign land cannot be built on")
	ger.treasury = 0.0
	jobs = ger.construction.size()
	var other := 0
	for p in ger.provinces:
		if p != id and Eco.build_problem(gs, "GER", p, "factory").is_empty():
			other = p
			break
	map_view.select(other)
	_check(ger.construction.size() == jobs + 1, "with an empty treasury it is still queued: " + panel._status.text)
	ger.treasury = 5000.0


func _test_retool_and_hover() -> void:
	var ger = _ger()
	panel._rows["military_factory"].pressed.emit()
	var id := 0
	for p in ger.provinces:
		if gs.province_buildings[p].get("factory", 0) >= 1:
			id = p
			break
	var civ: int = gs.province_buildings[id].get("factory", 0)
	_check(panel.act_on(id, true), "Ctrl+click retools a civilian factory")
	_check(gs.province_buildings[id].get("factory", 0) == civ - 1, "the civilian factory stops working")
	_check(panel._status.text.contains("Retooling"), "and the panel says so")
	panel._rows["port"].pressed.emit()
	_check(not panel.act_on(id, true) and panel._status.text.contains("factories"), "only factories can be retooled")
	panel._rows["railway"].pressed.emit()
	panel._on_province_hovered(id)
	_check(panel._status.text.contains(MapData_name(id)), "hovering names the province: " + panel._status.text)


func MapData_name(id: int) -> String:
	return root.get_node("MapData").provinces[id].name


func _test_close_and_mass() -> void:
	var ger = _ger()
	panel._mass_toggle.button_pressed = true
	await process_frame
	panel._rows["railway"].pressed.emit()
	ger.treasury = 5000.0
	panel._refresh()
	_check(panel._mass_box.visible and panel._mass_preview.text.contains("£"), "mass build previews: " + panel._mass_preview.text)
	var jobs: int = ger.construction.size()
	panel._mass_button.pressed.emit()
	_check(ger.construction.size() > jobs, "mass build queues the buildings")
	# Changing the map mode by hand leaves the panel open but stops it building.
	map_view.set_mode(MapView.Mode.TERRAIN)
	await process_frame
	_check(panel.picked() == "" and not panel._rows["railway"].button_pressed, "another map mode unlights the building")
	jobs = ger.construction.size()
	map_view.select(ger.provinces[3])
	_check(ger.construction.size() == jobs, "and a click then only selects")
	map_view.set_mode(MapView.Mode.POLITICAL)
	panel.select_type("factory")
	panel.toggle()
	await process_frame
	_check(not panel.visible and map_view.mode == MapView.Mode.POLITICAL, "closing the panel puts the map back")
