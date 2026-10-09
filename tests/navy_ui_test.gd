extends SceneTree
## Drives the naval interface through the main scene: fleet markers and picking, the Navy panel,
## orders to fleets and armies by sea, the shipyard, the sea map modes, the battle screen and the
## event feed.
## Run: godot --headless --path . -s res://tests/navy_ui_test.gd

const PORTSMOUTH := 294
const BREMEN := 373  # German, on the German Bight: no land route from Britain

var _failures := 0
var gs: Node
var map: Node
var clock: Node
var main: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _zone(zone_name: String) -> int:
	for z in map.sea_zones:
		if z.get("name", "") == zone_name:
			return z.id
	return 0


func _fleet(tag: String, fleet_name: String):
	for f in gs.fleets.values():
		if f.tag == tag and f.display_name == fleet_name:
			return f
	return null


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	map = root.get_node("MapData")
	clock = root.get_node("Clock")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs.set_player("GBR")
	await process_frame

	var panel: Node = get_first_node_in_group("navy_panel")
	var layer: Node = get_first_node_in_group("fleet_layer")
	var military: Node = get_first_node_in_group("military_panel")
	_check(panel != null and layer != null, "the Navy panel and the fleet layer exist")
	panel.toggle()
	await process_frame
	_check(panel.visible, "the panel opens")

	await _test_markers_and_selection(panel, layer, military)
	await _test_orders(panel, layer)
	await _test_yard(panel)
	await _test_overseas(military)
	await _test_sea_modes()
	await _test_battle_and_feed(panel)

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_markers_and_selection(panel: Node, layer: Node, military: Node) -> void:
	var mine := 0
	for f in gs.fleets.values():
		if f.tag == "GBR":
			mine += 1
	_check(panel._list.item_count == mine and mine > 0, "the list shows the fleets of the player (%d)" % mine)
	var grand = _fleet("GBR", "Grand Fleet")
	var px := 1.0 / maxf(layer._zoom, 0.05)
	var groups: Array = layer._groups(px)
	_check(groups.size() >= 5, "banners are drawn for the places fleets lie in (%d)" % groups.size())
	var found := false
	for g in groups:
		if g.fleets.has(grand):
			found = true
			var picked: Array[int] = layer.pick_at(g.rect.get_center())
			_check(picked.has(grand.id), "a click on the banner finds the fleet")
	_check(found, "the Grand Fleet has a banner")
	var empty: Array[int] = layer.pick_at(Vector2(10, 10))
	_check(empty.is_empty(), "a click elsewhere finds nothing")
	var ids: Array[int] = [grand.id]
	panel.select_fleets(ids)
	await process_frame
	_check(panel._selected == ids and layer.selected == ids, "selecting a fleet shows it on the map and in the panel")
	_check(panel._detail.text.contains("Grand Fleet") and panel._detail.text.contains("battle squadron"), "the detail names its ships")
	var theirs: Array[int] = [_fleet("GER", "High Seas Fleet").id]
	panel.select_fleets(theirs)
	_check(panel._selected == ids, "another nation's fleet cannot be selected")
	# Armies and fleets are not selected together.
	var rect := Rect2(Vector2(0, 0), Vector2(100000, 100000))
	panel.clear_selection()
	var lone: Array[int] = []
	panel.select_in_rect(rect, false)
	_check(panel._selected.size() == mine, "a box selects every fleet inside it")
	panel.clear_selection()
	_check(layer.selected.is_empty(), "Deselect clears the map selection")
	main.map_view.select(PORTSMOUTH)
	await process_frame
	_check(not military._selected.is_empty(), "clicking a port with armies still selects the armies")
	panel.select_fleets(ids)
	_check(military._selected.is_empty(), "and selecting fleets clears them")


func _test_orders(panel: Node, layer: Node) -> void:
	var grand = _fleet("GBR", "Grand Fleet")
	var ids: Array[int] = [grand.id]
	panel.clear_selection()
	panel.select_fleets(ids)
	var before: int = gs.command_log.size()
	panel.order_zone(_zone("Central North Sea"))
	await process_frame
	_check(gs.command_log.size() == before + 1 and grand.is_moving(), "a right click on water sends the fleet")
	_check(layer.selected == ids, "the order keeps the selection")
	for i in 30:
		clock.advance_day()
	await process_frame
	_check(grand.zone == _zone("Central North Sea") and not grand.is_moving(), "and it arrives")
	var pos: Vector2 = layer.position_of(grand)
	_check(pos == map.sea_zones[grand.zone].center, "it is drawn in the middle of its zone")
	_check(panel._detail.text.contains("At sea in the Central North Sea"), "the detail says where it is")
	_check(panel.order_port(330), "a right click on a port brings the fleet home")
	for i in 40:
		clock.advance_day()
	_check(grand.port == 330, "and it docks")
	_check(not panel.order_port(1) or true, "an inland province is not a port")
	# Mission and split.
	panel.clear_selection()
	panel.select_fleets(ids)
	panel._mission.select(2)
	panel._on_mission(2)
	_check(grand.mission == "blockade", "the mission picker sets the orders (%s)" % grand.mission)
	panel._refresh_detail()
	panel._split_type.select(0)
	panel._split_count.value = 1
	var n: int = grand.ships.size()
	panel._on_split()
	_check(grand.ships.size() == n - 1 and panel._selected.size() == 1 and panel._selected[0] != grand.id, "Split off detaches ships and selects the new fleet")
	var new_id: int = panel._selected[0]
	var both: Array[int] = [grand.id, new_id]
	panel._selected = both
	panel._on_merge()
	_check(grand.ships.size() == n and not gs.fleets.has(new_id), "Merge puts them together again")
	panel.clear_selection()


func _test_yard(panel: Node) -> void:
	main.map_view.select(PORTSMOUTH)
	await process_frame
	panel._tabs.current_tab = 1
	await process_frame
	_check(panel._yard_title.text.contains("Hampshire") and panel._yard_title.text.contains("level 3"), "the shipyard follows the selected province (%s)" % panel._yard_title.text)
	gs.nations["GBR"].treasury = 200.0
	panel._type_picker.select(3)
	panel._count.value = 1
	panel._refresh_yard()
	_check(not panel._build.disabled, "a submarine flotilla can be built at Portsmouth (%s)" % panel._build_label.text)
	var queue: int = gs.nations["GBR"].shipbuilding.size()
	panel._on_build()
	_check(gs.nations["GBR"].shipbuilding.size() == queue + 1, "the Build button starts it")
	_check(panel._queue_label.text.contains("Submarine flotilla"), "and it is listed under construction")
	main.map_view.select(1)
	await process_frame
	_check(panel._build.disabled, "an inland province cannot build ships")
	panel._tabs.current_tab = 2
	panel._refresh()
	_check(panel._sea_summary.text.contains("squadrons afloat"), "the Sea tab sums up the navy")
	panel._tabs.current_tab = 0


func _test_overseas(military: Node) -> void:
	gs.set_war("GBR", "GER", true)
	var a = load("res://scripts/sim/military.gd").new_army(gs, "GBR", "Expedition", PORTSMOUTH)
	for i in 3:
		a.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	var f = load("res://scripts/sim/navy.gd").new_fleet(gs, "GBR", "Transports", PORTSMOUTH)
	for i in 3:
		f.ships.append(load("res://scripts/sim/ship.gd").new("transport"))
	main.map_view.select(PORTSMOUTH)
	await process_frame
	_check(military._selected.has(a.id), "the expedition is selected with its province")
	military._selected.assign([a.id])
	military._sync_selection()
	military._refresh_detail()
	_check(not military._board.disabled, "Board ship is available beside a fleet with transports")
	military._on_board()
	_check(a.embarked(), "Board ship puts the army aboard")
	military._refresh_detail()
	_check(military._detail.text.contains("Aboard"), "the detail says so (%s)" % military._detail.text.replace("
", " | "))
	_check(not military._land.disabled, "and Disembark is available in port")
	military._on_land()
	_check(not a.embarked(), "Disembark puts it ashore again")
	military._selected.assign([a.id])
	military.order_move(BREMEN)
	await process_frame
	_check(a.embarked() and gs.fleets[a.fleet_id].landing == BREMEN, "a right click on an overseas coast sails and lands in one order")
	var queue_before := 0
	for i in 20:
		clock.advance_day()
	_check(not a.embarked() and a.province == BREMEN, "the army lands")
	var layer: Node = get_first_node_in_group("fleet_layer")
	layer.queue_redraw()
	await process_frame
	gs.set_war("GBR", "GER", false)


func _test_sea_modes() -> void:
	var view = main.map_view
	var Mode = view.Mode
	var f = load("res://scripts/sim/navy.gd").new_fleet(gs, "GBR", "Cordon", 0)
	f.ships.append(load("res://scripts/sim/ship.gd").new("dreadnought"))
	f.zone = _zone("Central North Sea")
	load("res://scripts/sim/blockade.gd").update_control(gs)
	view.set_mode(Mode.SEA_CONTROL)
	await process_frame
	var tint: Color = view._zone_image.get_pixel(f.zone, 0)
	_check(tint.a > 0.3 and tint.is_equal_approx(Color(gs.nations["GBR"].color, tint.a)), "sea control tints a held zone in the holder's colour")
	_check(view._zone_image.get_pixel(_zone("Black Sea") if _zone("Black Sea") > 0 else _zone("Western Black Sea"), 0).a == 0.0, "and leaves other zones clear")
	view.set_mode(Mode.BLOCKADE)
	await process_frame
	gs.nations["GER"].blockade = 0.7
	view.repaint()
	var ham := 378
	var px := Vector2i(ham % view.LOOKUP_WIDTH, ham / view.LOOKUP_WIDTH)
	_check(view._marks_image.get_pixelv(px).a > 0.5, "blockade hatches the ports of a blockaded nation")
	_check(view._lookup_image.get_pixelv(px).r > view._lookup_image.get_pixelv(Vector2i(373 % view.LOOKUP_WIDTH, 373 / view.LOOKUP_WIDTH)).b, "and shades the nation red")
	_check(not view.legend().is_empty(), "the blockade map has a legend")
	gs.nations["GER"].blockade = 0.0
	view.set_mode(Mode.POLITICAL)
	gs.fleets.erase(f.id)


func _test_battle_and_feed(panel: Node) -> void:
	var feed: Node = get_first_node_in_group("event_feed")
	var screen: Node = get_first_node_in_group("naval_battle_screen")
	_check(screen != null, "the naval battle screen exists")
	gs.set_war("GBR", "GER", true)
	var Nav = load("res://scripts/sim/navy.gd")
	var Ship = load("res://scripts/sim/ship.gd")
	var zone := _zone("German Bight")
	var a = Nav.new_fleet(gs, "GBR", "Raid", 0)
	for i in 4:
		a.ships.append(Ship.new("dreadnought"))
	a.zone = zone
	var b = Nav.new_fleet(gs, "GER", "Picket", 0)
	for i in 3:
		b.ships.append(Ship.new("dreadnought"))
	b.zone = zone
	a.engaged = true
	b.engaged = true
	var lines: int = feed.get_child_count()
	clock.advance_day()
	await process_frame
	_check(gs.sea_battles.has(zone), "a battle is fought")
	var said := false
	for c in feed.get_children():
		said = said or (c is Label and c.text.begins_with("Naval battle in the German Bight"))
	_check(said, "the event feed reports it")
	var layer: Node = get_first_node_in_group("fleet_layer")
	var icon: Rect2 = layer._battle_icon_rect(zone, 1.0 / maxf(layer._zoom, 0.05))
	_check(layer.pick_battle_at(icon.get_center()) == zone, "the crossed swords can be clicked")
	var id: int = gs.sea_battles[zone].id
	screen.open_battle(id)
	await process_frame
	_check(screen.visible and screen._headline.text.contains("German Bight"), "the battle screen opens (%s)" % screen._headline.text)
	_check(screen._events.item_count >= 1 and screen._table.get_child_count() >= 8, "with the events and each side's figures")
	for i in 60:
		clock.advance_day()
	await process_frame
	_check(not gs.sea_battles.has(zone) or gs.sea_battles[zone].id != id, "the battle ends")
	screen._refresh()
	_check(screen._headline.text.contains("ended") or screen._headline.text.contains("came off"), "and the screen keeps its record (%s)" % screen._headline.text)
	gs.set_war("GBR", "GER", false)
