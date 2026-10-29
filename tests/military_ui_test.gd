extends SceneTree
## Drives the military UI through the main scene: selecting armies, ordering a march, merging.
## Run: godot --headless --path . -s res://tests/military_ui_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var Mil = load("res://scripts/sim/military.gd")
	var panel: Node = get_first_node_in_group("military_panel")
	var layer: Node = get_first_node_in_group("army_layer")
	_check(panel != null and layer != null, "panel and army layer exist")
	panel.toggle()
	await process_frame

	var nancy := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Meurthe-et-Moselle":
			nancy = id
	gs.set_player("FRA")
	await process_frame
	main.map_view.select(nancy)
	await process_frame
	_check(panel._selected.size() == 1, "clicking a province selects the armies in it (%d)" % panel._selected.size())
	_check(layer.selected == panel._selected, "the map layer shows the selection")

	# Orders.
	var dest := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "FRA":
			dest = n
	var before: int = gs.command_log.size()
	panel.order_move(dest)
	await process_frame
	var army = gs.armies[panel._selected[0]]
	_check(gs.command_log.size() == before + 1 and not army.path.is_empty(), "a right click issues a move command")
	for i in 40:
		root.get_node("Clock").advance_day()
	await process_frame
	_check(army.province == dest or gs.armies.has(army.id), "the army marches while days pass")

	# Recruit and war switches.
	panel.set_province(nancy)
	panel._on_raise()
	await process_frame
	_check(gs.nations["FRA"].recruiting.size() == 1, "the Raise button queues a division")

	# Deselecting.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()  # the scenario starts with Austria-Hungary at war with Serbia; these tests want a clean slate
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	panel.set_province(nancy)
	_check(panel._selected.size() == 1, "clicking a province with your armies selects them")
	panel.set_province(nancy)
	_check(panel._selected.is_empty() and layer.selected.is_empty(), "clicking the same province again deselects")
	panel.set_province(nancy)
	panel.set_province(0)
	_check(panel._selected.is_empty(), "clicking empty ground deselects")
	panel.set_province(nancy)
	var paris := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Savoie" and gs.province_owner[id] == "FRA":
			paris = id
	panel.set_province(paris)
	_check(panel._selected.size() == 1 and gs.armies[panel._selected[0]].province == paris, "clicking another army's province switches the selection")
	panel.clear_selection()
	_check(panel._selected.is_empty(), "clear_selection (Esc, button) deselects")

	# A front by clicking the neighbouring nation.
	var german := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Moselle":
			german = id
	panel._begin_picking_nation()
	_check(panel._picking_nation and panel._face_row.visible, "the nation picker opens")
	panel.set_province(german)
	_check(not panel._picking_nation and panel._front_ids.size() == 1, "clicking a German province draws the front against Germany")
	var face = gs.fronts[panel._front_ids[0]]
	_check(face.against == "GER" and not face.provinces.is_empty(), "it follows the German border (%d provinces)" % face.provinces.size())
	panel._begin_picking_nation()
	panel.set_province(nancy)
	_check(panel._picking_nation, "clicking your own province does not make a front against yourself")
	panel._end_drawing()
	panel._on_delete_front()

	# Plans of attack: select an army, mark a line to push to, add a phase, launch, halt; then a spearhead.
	main.map_view.select(nancy)
	await process_frame
	var planner = gs.armies[panel._selected[0]]
	panel._refresh_fronts()
	_check(not panel._plan_push.disabled and panel._plan_launch.disabled and panel._plan_label.text.contains("no plan"), "with an army selected, a plan can be made: %s" % panel._plan_label.text)
	var targets: Array[int] = []
	for n: int in Mil.neighbors(nancy):
		if gs.province_controller[n] == "GER":
			targets.append(n)
	panel._begin_picking("push", "")
	for t in targets:
		panel._add_to_draft(t)
	panel._finish_drawing()
	var plan = load("res://scripts/sim/offensives.gd").of_army(gs, planner)
	_check(plan != null and plan.kind == "broad" and plan.targets().size() == targets.size(), "clicking German provinces and Finish makes a push to them (%d)" % targets.size())
	panel._begin_picking("phase", "")
	panel._add_to_draft(german)
	panel._finish_drawing()
	_check(plan != null and plan.phases.size() == 2, "Add phase adds a second line")
	panel._plan_aggr.item_selected.emit(2)
	_check(plan != null and plan.aggressiveness == "aggressive", "the aggressiveness is set from the list")
	panel._on_launch()
	_check(plan != null and plan.active and panel._plan_launch.text == "Halt", "Launch launches it, and the button turns to Halt")
	panel._on_launch()
	_check(plan != null and not plan.active, "Halt halts it")
	panel._begin_picking("spearhead", "")
	panel._add_to_draft(german)
	var spear = load("res://scripts/sim/offensives.gd").of_army(gs, planner)
	_check(spear != null and spear.kind == "spearhead" and spear.targets() == [german], "Spearhead and one click aims the army at one province, replacing the push")
	panel._plan_cancel.pressed.emit()
	_check(load("res://scripts/sim/offensives.gd").of_army(gs, planner) == null, "Cancel drops the plan")

	# Battle screen.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()  # the scenario starts with Austria-Hungary at war with Serbia; these tests want a clean slate
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	gs.armies.clear()
	gs.set_war("FRA", "GER", true)
	var german_province := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Moselle":
			german_province = id
	var atk = Mil.new_army(gs, "FRA", "Attackers", german_province)
	var dfn = Mil.new_army(gs, "GER", "Defenders", german_province)
	for i in 6:
		atk.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
		dfn.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	atk.units.append(load("res://scripts/sim/unit.gd").new("artillery"))
	atk.attacking = true
	dfn.still_days = 30
	var screen: Node = get_first_node_in_group("battle_screen")
	_check(screen != null and not screen.visible, "the battle screen exists and starts closed")
	root.get_node("Clock").advance_day()
	root.get_node("Clock").advance_day()
	await process_frame
	await process_frame
	_check(not gs.battle_at(german_province).is_empty(), "a battle is under way")
	var icon_centre: Vector2 = layer._battle_icon_rect(german_province, 1.0 / layer._zoom).get_center()
	_check(layer.pick_battle_at(icon_centre) == german_province, "its icon can be picked on the map")
	_check(layer.pick_battle_at(icon_centre + Vector2(2000, 2000)) == 0, "but not elsewhere")
	main.map_view.battle_clicked.emit(german_province)
	await process_frame
	_check(screen.visible and screen._title.text == "Battle of Moselle", "clicking the icon opens the battle screen")
	_check(screen._status.text.begins_with("In progress"), "which says the battle is in progress (%s)" % screen._status.text)
	_check(screen._sides.get_child_count() == 2, "it shows both sides")
	_check(screen._morale_chart.series.size() == 2 and screen._morale_chart.series[0].points.size() >= 3, "the morale chart has a line per side with the days so far")
	_check(screen._morale_chart.percent and screen._events.item_count >= 1, "morale chart and event list are filled in")
	var points_before: int = screen._morale_chart.series[0].points.size()
	root.get_node("Clock").advance_day()
	await process_frame
	_check(screen._morale_chart.series[0].points.size() == points_before + 1, "an open screen follows the battle day by day")
	var guard := 0
	while not gs.engagements.is_empty() and guard < 120:
		root.get_node("Clock").advance_day()
		guard += 1
	await process_frame
	_check(screen._status.text.begins_with("Ended") and screen._status.text.contains("won"), "when it ends the screen says who won (%s)" % screen._status.text)
	screen.close_screen()
	_check(not screen.visible, "it can be closed")
	# Finished battles open from the Wars tab.
	panel.visible = true
	panel._refresh()
	panel._refresh_wars()
	_check(panel._war_battles.item_count == 1 and not panel._war_battles.get_item_text(0).begins_with("●"), "a finished battle is listed in the Wars section")
	panel._open_battle(panel._war_battle_ids[0])
	await process_frame
	_check(screen.visible and screen._title.text == "Battle of Moselle", "and opens its screen")
	screen.close_screen()
	var log_battles := 0
	for i in panel._war_log.item_count:
		if panel._war_log.get_item_metadata(i).battle > 0:
			log_battles += 1
	_check(log_battles == 1, "the war log entry for the battle carries its id")

	# Wars section.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()  # the scenario starts with Austria-Hungary at war with Serbia; these tests want a clean slate
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	panel.visible = true
	panel._refresh()
	_check(not panel._fronts_box.visible and not panel._recruit_box.visible and not panel._wars_box.visible, "the Military page opens with Fronts, Recruit and Wars folded")
	panel.show_tab("Recruit")
	_check(panel._recruit_box.visible, "show_tab(\"Recruit\") unfolds that section")
	panel.set_section("Recruit", false)
	_check(panel._wars_list.item_count == 0 and panel._war_summary.text.contains("No wars"), "it starts empty")
	gs.set_war("FRA", "GER", true)
	gs.set_war("GBR", "ITA", true)
	panel._refresh_wars()
	_check(panel._wars_list.item_count == 2, "wars appear in the list (%d)" % panel._wars_list.item_count)
	_check(panel._wars_list.get_item_text(0).begins_with("France vs German Empire") and panel._wars_list.get_item_text(0).contains("ongoing"), "the player's wars come first and say they are ongoing")
	_check(panel._war_summary.text.contains("France attacked German Empire"), "the summary says who attacked")
	_check(panel._war_cells[0][1].text == "France" and panel._war_cells[0][2].text == "German Empire", "the table is headed by the two nations")
	_check(panel._war_log.item_count == 1 and panel._war_log.get_item_text(0).contains("declares war"), "the log has the declaration")
	var war = gs.war_between("FRA", "GER")
	war.losses["FRA"] = 12000.0
	war.captured["FRA"].provinces = 2
	war.captured["FRA"].population = 1500000
	war.add_battle({"province": nancy, "name": "Nancy", "date": "1 August 1914", "end_date": "3 August 1914", "days": 3, "attacker": "FRA", "winner": "FRA", "strength": {"FRA": 50000.0, "GER": 40000.0}, "lost": {"FRA": 12000.0, "GER": 15000.0}})
	war.add_log("3 August 1914", "battle", "Battle of Nancy (3 days): France lost 12k of 50k, German Empire lost 15k of 40k. France won.", nancy)
	panel._refresh_wars()
	var rows := {}
	for r in panel._war_cells:
		rows[r[0].text] = r
	_check(rows["Lost in battle"][1].text == "12k" and rows["Provinces taken"][1].text == "2" and rows["People taken"][1].text == "1.5M", "losses and gains show in the table")
	_check(rows["Battles won"][1].text == "1" and rows["Battles lost"][2].text == "1", "battle results show per nation")
	_check(panel._war_log.item_count == 2 and panel._war_log.get_item_text(0).contains("Battle of Nancy"), "newest entries come first")
	panel._war_filter.select(1)
	panel._war_log_key = ""
	panel._refresh_wars()
	_check(panel._war_log.item_count == 1, "the filter shows battles only")
	panel._war_filter.select(0)
	gs.set_war("FRA", "GER", false)
	panel._refresh_wars()
	_check(panel._wars_list.get_item_text(0).contains("ended") and rows["Enemy land held now"][1].text == "—", "ended wars say so and stay listed")
	_check(panel._war_log.item_count == 3, "the peace is logged")
	var collapsed_feed := 0
	for c in get_nodes_in_group("event_feed"):
		collapsed_feed += 1
	_check(collapsed_feed == 1, "the event feed is in place")

	# Several armies on one tile are shown one by one.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()  # the scenario starts with Austria-Hungary at war with Serbia; these tests want a clean slate
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	main.map_view.select(nancy)
	await process_frame
	_check(layer._expanded == nancy and layer._expanded_layout(1.0).is_empty(), "a tile with one army is not fanned out")
	var extra = Mil.new_army(gs, "FRA", "Second Army", nancy)
	extra.units.append(load("res://scripts/sim/unit.gd").new("cavalry"))
	var foreign = Mil.new_army(gs, "GER", "Visitors", nancy)
	foreign.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	gs.armies_changed.emit()
	main.map_view.select(nancy)
	await process_frame
	await process_frame
	var layout: Array = layer._expanded_layout(1.0)
	_check(layout.size() == 2, "every army the player sees exactly on the selected tile gets its own banner (%d)" % layout.size())
	_check(layout[0].army.tag == "FRA" and layout[1].army.tag == "FRA" and layer.seen(foreign) == 1, "the visitors are not fanned out: they stay an estimate banner")
	var seen := {}
	for entry in layout:
		seen[entry.army.id] = true
	_check(seen.size() == 2, "each banner is a different army")
	for i in layout.size():
		for j in range(i + 1, layout.size()):
			_check(not layout[i].rect.intersects(layout[j].rect), "banners %d and %d do not overlap" % [i, j])
	var zoom: float = layer._zoom
	var target: Dictionary = layout[1]
	var scaled: Array = layer._expanded_layout(1.0 / zoom)
	var point: Vector2 = scaled[1].rect.get_center()
	_check(layer.pick_at(point) == target.army.id, "clicking a banner picks that army")
	_check(layer.pick_at(Vector2(-1000, -1000)) == 0, "clicking elsewhere picks nothing")
	var selected_before: int = panel._selected.size()
	_check(selected_before == 2, "selecting the tile selects all of your armies on it (%d)" % selected_before)
	panel.select_army(target.army.id)
	_check(panel._selected == [target.army.id], "clicking one banner narrows the selection to it")
	panel.select_army(target.army.id)
	_check(panel._selected.is_empty(), "clicking it again deselects")
	panel.select_army(layout[0].army.id)
	panel.select_army(layout[1].army.id, true)
	_check(panel._selected.size() == 2, "Shift adds an army")
	panel.select_army(layout[1].army.id, true)
	_check(panel._selected.size() == 1, "Shift on a selected army removes it")
	panel.select_army(foreign.id)
	_check(not panel._selected.has(foreign.id), "a foreign army is never selected")
	panel.clear_selection()

	# The map draws compositions without errors (selected army, then the fanned-out tile).
	main.map_view.select(nancy)
	layer.queue_redraw()
	await process_frame
	await process_frame
	var comp_army = gs.armies[panel._selected[0]]
	_check(not comp_army.composition().is_empty() and layer.selected.has(comp_army.id), "a selected army has a composition to draw")

	# Box selection.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()  # the scenario starts with Austria-Hungary at war with Serbia; these tests want a clean slate
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	panel._selected.clear()
	var lorraine: Vector2 = map.provinces[nancy].center
	panel.select_in_rect(Rect2(lorraine - Vector2(200, 200), Vector2(400, 400)))
	var inside := 0
	for a in Mil.armies_of(gs, "FRA"):
		if Rect2(lorraine - Vector2(200, 200), Vector2(400, 400)).has_point(map.provinces[a.province].center):
			inside += 1
	_check(inside >= 2 and panel._selected.size() == inside, "a dragged box selects every army inside it (%d)" % inside)
	_check(layer.selected == panel._selected, "and the map layer follows")
	panel.select_in_rect(Rect2(Vector2(-500, -500), Vector2(10, 10)))
	_check(panel._selected.is_empty(), "an empty box clears the selection")
	var before_ids: Array[int] = []
	panel.select_in_rect(Rect2(lorraine - Vector2(200, 200), Vector2(400, 400)))
	before_ids = panel._selected.duplicate()
	panel.select_in_rect(Rect2(Vector2(-500, -500), Vector2(10, 10)), true)
	_check(panel._selected == before_ids, "Shift keeps the existing selection")

	# Drawing a front on the map.
	panel._begin_drawing()
	panel.set_province(nancy)
	var far_province := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "FRA":
			far_province = n
	panel.set_province(far_province)
	_check(panel._draft.size() == 2 and layer._draft.size() == 2, "clicking provinces builds the draft line")
	panel.set_province(far_province)
	_check(panel._draft.size() == 1, "clicking the last province again removes it")
	panel.set_province(far_province)
	panel.order_move(nancy)
	_check(panel._drawing, "right clicks are ignored while drawing")
	panel._front_name.text = "Test Front"
	panel._finish_drawing()
	_check(not panel._drawing and panel._front_ids.size() == 1, "finishing creates the front")
	panel._on_assign()
	await process_frame
	_check(gs.fronts[panel._front_selected].army_ids.size() == panel._selected.size(), "Assign puts the selected armies on it")
	panel._on_release()
	_check(gs.fronts[panel._front_selected].army_ids.is_empty(), "Release takes them off")
	panel._on_delete_front()
	_check(gs.fronts.is_empty(), "Delete removes the front")

	# The panel never reaches the map mode bar.
	panel.visible = true
	panel._refresh()
	await process_frame
	await process_frame
	var bottom: float = panel.get_global_rect().end.y
	var limit: float = root.get_visible_rect().size.y - 120.0
	_check(bottom <= limit, "the military panel stops above the map mode bar (%d <= %d)" % [bottom, limit])

	# Map modes.
	var view: Node = main.map_view
	for m in [6, 7, 0]:
		view.set_mode(m)
		await process_frame
	_check(view.mode == 0, "terrain and military map modes paint without errors")

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)
