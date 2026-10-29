extends SceneTree
## Drives the Battle Plans toolbar through the main scene, as the map would (BattlePlanToolbar.map_press / map_drag /
## map_release): each tool's order, Execute and the aggressiveness, Unassign, Delete (one order and all), Esc, and the
## command panel's add-commander card.
## Run: godot --headless --path . -s res://tests/battle_plan_toolbar_test.gd

var _failures := 0
var gs: Node
var clock: Node
var MD: Node
var Mil
var Off
var bar: Node
var panel: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_toolbar_settings.cfg"
	load("res://scripts/ui/ui_settings.gd").command_open = true
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	MD = root.get_node("MapData")
	Mil = load("res://scripts/sim/military.gd")
	Off = load("res://scripts/sim/offensives.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.set_war("GER", "RUS", true)
	gs.pending_joins.clear()
	await process_frame
	bar = get_first_node_in_group("battle_plan_toolbar")
	panel = get_first_node_in_group("military_panel")
	_check(bar != null and get_first_node_in_group("map_tool") == bar, "the toolbar is there and takes the map's clicks while a tool is in hand")
	_check(bar._paradrop.disabled, "Paradrop stays off: there are no aircraft")
	await _test_fronts_and_plans()
	await _test_fallback_and_garrison()
	await _test_invasion_and_support()
	await _test_delete_and_commander(main)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_toolbar_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## The German port (one ships can lie in) nearest to Danzig.
func _port() -> int:
	var danzig: Vector2 = MD.provinces[_named("Danzig")].center
	var best := 0
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER" and load("res://scripts/sim/navy.gd").can_dock(gs, "GER", id):
			if best == 0 or (MD.provinces[id].center as Vector2).distance_to(danzig) < (MD.provinces[best].center as Vector2).distance_to(danzig):
				best = id
	return best


func _named(city: String) -> int:
	for c in gs.cities:
		if c.name == city:
			return c.province
	return 0


## A German army of `n` divisions at a province, selected.
func _army(at: int, n: int):
	var a = Mil.new_army(gs, "GER", "Test Army %d" % gs.next_army_id, at)
	for i in n:
		a.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	panel.select_ids([a.id] as Array[int])
	await process_frame
	return a


func _test_fronts_and_plans() -> void:
	var border: Array[int] = Mil.border_provinces(gs, "GER", "RUS")
	var mine: int = border[border.size() / 2]
	var across := 0
	for n: int in Mil.neighbors(mine):
		if gs.province_controller[n] == "RUS":
			across = n
	var army = await _army(mine, 6)
	_check(bar.roots() == [army] and bar._status.text.contains("no plan"), "the toolbar acts on the selected army (%s)" % bar._status.text)
	bar.set_tool("offensive")
	_check(bar.tool == "", "an army on no front cannot be given an offensive line")
	# Front line: click across the border; Shift for the whole border.
	bar.set_tool("front")
	_check(bar.tool == "front" and bar._hint.visible and bar._hint.text.contains("Front line"), "the Front line tool is in hand, with its hint")
	bar.map_press(across, 0, MOUSE_BUTTON_LEFT, false)
	var front = gs.fronts.get(army.front_id)
	_check(front != null and front.against == "RUS" and front.anchor == across and bar.tool == "", "clicking the border puts the army on a front there, and the tool is put down")
	bar.set_tool("front")
	bar.map_press(across, 0, MOUSE_BUTTON_LEFT, true)
	var whole = gs.fronts.get(army.front_id)
	_check(whole != null and whole.anchor == 0 and whole.provinces.size() == border.size(), "Shift+click takes the whole border (%d provinces)" % border.size())
	# Offensive line: a drag across Russian ground.
	var ring: Array[int] = []
	for p in Mil.border_provinces(gs, "RUS", "GER"):
		ring.append(p)
	bar.set_tool("offensive")
	bar.map_press(ring[0], 0, MOUSE_BUTTON_RIGHT, false)
	for p in ring.slice(1, 4):
		bar.map_drag(p)
	bar.map_drag(mine)  # own ground is not part of an offensive line
	bar.map_release(ring[3], MOUSE_BUTTON_RIGHT)
	var plan = Off.of_army(gs, army)
	_check(plan != null and plan.kind == "broad" and plan.targets() == ring.slice(0, 4), "dragging across enemy ground draws the line to push to")
	bar.set_tool("offensive")
	bar.map_press(ring[4], 0, MOUSE_BUTTON_RIGHT, false)
	bar._drawing = false
	bar._finish_offensive(true)
	_check(plan.phases.size() == 2, "with Shift a further line is the next phase")
	# Execute and aggressiveness.
	_check(not bar._execute.disabled and not bar._execute.button_pressed, "Execute is open once there is a plan")
	bar._on_execute()
	_check(plan.active and bar._execute.button_pressed, "Execute launches it")
	bar._on_aggressiveness(0)
	_check(plan.aggressiveness == "careful" and bar._aggr[0].button_pressed and not bar._aggr[1].button_pressed, "Careful is set on the plan")
	bar._on_execute()
	_check(not plan.active, "Execute again halts it")
	# Spearhead, then Edit moves its target.
	bar.set_tool("spearhead")
	bar.map_press(mine, 0, MOUSE_BUTTON_LEFT, false)
	_check(bar.tool == "spearhead", "a spearhead is not aimed at your own ground")
	bar.map_press(ring[1], 0, MOUSE_BUTTON_RIGHT, false)
	var spear = Off.of_army(gs, army)
	_check(spear.kind == "spearhead" and spear.targets() == [ring[1]] and spear.aggressiveness == "careful", "Spearhead aims at the province clicked, at the aggressiveness set")
	bar.set_tool("edit")
	bar.map_press(ring[2], 0, MOUSE_BUTTON_LEFT, false)
	bar.map_release(ring[2], MOUSE_BUTTON_LEFT)
	_check(spear.targets() == [ring[2]] and bar.tool == "edit", "Edit moves a spearhead's target to the province clicked")
	# Edit a push: drag on to add, drag from a province of the line to take off.
	bar.set_tool("offensive")
	bar.map_press(ring[0], 0, MOUSE_BUTTON_RIGHT, false)
	bar.map_drag(ring[1])
	bar.map_release(ring[1], MOUSE_BUTTON_RIGHT)
	var push = Off.of_army(gs, army)
	bar.set_tool("edit")
	bar.map_press(ring[2], 0, MOUSE_BUTTON_LEFT, false)
	bar.map_drag(ring[3])
	bar.map_release(ring[3], MOUSE_BUTTON_LEFT)
	_check(push.targets() == [ring[0], ring[1], ring[2], ring[3]], "Edit adds the provinces dragged over to the line")
	bar.map_press(ring[0], 0, MOUSE_BUTTON_LEFT, false)
	bar.map_release(ring[0], MOUSE_BUTTON_LEFT)
	_check(not push.targets().has(ring[0]) and push.targets().size() == 3, "and takes off one it starts on")
	# Esc puts the tool down.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	bar._input(esc)
	_check(bar.tool == "" and not bar._hint.visible, "Esc puts the tool down")
	# Unassign.
	bar._on_unassign()
	_check(army.front_id == 0 and Off.of_army(gs, army) == null, "Unassign takes the army off its front and drops its plan")


func _test_fallback_and_garrison() -> void:
	var posen := _named("Posen")
	var army = await _army(posen, 4)
	var line: Array[int] = [posen]
	for n: int in Mil.neighbors(posen):
		if gs.province_controller[n] == "GER" and not Mil.neighbors(n).any(func(m: int) -> bool: return gs.province_controller[m] == "RUS"):
			line.append(n)
			break
	bar.set_tool("fallback")
	bar.map_press(line[0], 0, MOUSE_BUTTON_LEFT, false)
	bar.map_drag(line[1])
	bar.map_release(line[1], MOUSE_BUTTON_LEFT)
	var f = gs.fronts.get(army.front_id)
	_check(f != null and f.provinces == line and f.against == "", "dragging through your own ground draws a line and puts the army on it")
	# Edit the drawn line: extend it from its end.
	var further := 0
	for n: int in Mil.neighbors(line[1]):
		if gs.province_controller[n] == "GER" and not line.has(n) and not Mil.neighbors(line[0]).has(n):
			further = n
			break
	bar.set_tool("edit")
	bar.map_press(further, 0, MOUSE_BUTTON_LEFT, false)
	bar.map_release(further, MOUSE_BUTTON_LEFT)
	_check(f.provinces.size() == 3 and f.provinces.back() == further, "Edit lengthens a drawn line from its end")
	bar.set_tool("")
	# Garrison: the ports near a Baltic port.
	var danzig := _port()
	bar.set_tool("garrison")
	_check(bar._garrison_box.visible, "Garrison opens its checklist")
	for k: String in bar._garrison_checks:
		bar._garrison_checks[k].button_pressed = k == "port"
	bar.map_press(danzig, 0, MOUSE_BUTTON_LEFT, false)
	var picked: Array[int] = bar._stroke.duplicate()
	_check(not picked.is_empty() and picked.all(func(p: int) -> bool: return bar.guards(p, "port")), "a click with Ports ticked picks the ports near it (%d)" % picked.size())
	bar.finish_garrison()
	var g = gs.fronts.get(army.front_id)
	_check(g != null and g.kind == "garrison" and g.provinces == picked and bar.tool == "" and not bar._garrison_box.visible, "Finish makes the garrison and puts the army on it")


func _test_invasion_and_support() -> void:
	var danzig := _port()
	var army = await _army(danzig, 3)
	var coast := 0
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "RUS" and not MD.zones_of_port(id).is_empty():
			coast = id
			break
	bar.set_tool("invasion")
	bar.map_press(_named("Posen"), 0, MOUSE_BUTTON_LEFT, false)
	_check(bar._port == 0, "an invasion sails from a port, not from inland")
	bar.map_press(danzig, 0, MOUSE_BUTTON_LEFT, false)
	_check(bar._port == danzig and bar._hint.text.contains("click the coast"), "after the port it asks for the coast")
	bar.map_press(coast, 0, MOUSE_BUTTON_LEFT, false)
	var o = Off.of_army(gs, army)
	_check(o != null and o.kind == "invasion" and o.port == danzig and o.targets() == [coast] and bar.tool == "", "clicking the coast plans the landing")
	# Naval support.
	var warships: Array = bar._warship_fleets()
	bar.set_tool("support")
	if warships.is_empty():
		_check(bar.tool == "", "with no warships, Naval support cannot be taken up")
	else:
		bar.map_press(coast, 0, MOUSE_BUTTON_LEFT, false)
		var sent: Array = warships.filter(func(f) -> bool: return f.mission == "support")
		_check(sent.size() == 1 and (sent[0].is_moving() or MD.zones_of_port(coast).has(sent[0].current_zone())), "Naval support sends the nearest warships off the coast on Shore support")


func _test_delete_and_commander(main: Node) -> void:
	var border: Array[int] = Mil.border_provinces(gs, "GER", "RUS")
	var army = await _army(border[0], 4)
	bar.set_tool("front")
	bar.map_press(border[0], 0, MOUSE_BUTTON_LEFT, true)
	var target := 0
	for n: int in Mil.neighbors(border[0]):
		if gs.province_controller[n] == "RUS":
			target = n
	bar.set_tool("spearhead")
	bar.map_press(target, 0, MOUSE_BUTTON_LEFT, false)
	var front_id: int = army.front_id
	bar.set_tool("delete")
	bar.map_press(target, 0, MOUSE_BUTTON_LEFT, false)
	_check(Off.of_army(gs, army) == null and army.front_id == front_id and bar.tool == "delete", "Delete on a plan's target removes the plan; the tool stays in hand")
	bar.map_press(target, 0, MOUSE_BUTTON_LEFT, false)
	_check(not gs.fronts.has(front_id) and army.front_id == 0, "clicking the border again deletes the front and releases its army")
	bar.set_tool("")
	# Right click on Delete with nothing selected: every order of yours.
	bar.set_tool("front")
	bar.map_press(border[0], 0, MOUSE_BUTTON_LEFT, true)
	panel.clear_selection()
	await process_frame
	bar.clear_all_orders()
	_check(gs.fronts.values().all(func(f) -> bool: return f.tag != "GER") and gs.offensives.values().all(func(o) -> bool: return o.tag != "GER"), "clearing with nothing selected removes every front and plan of yours")
	# The add-commander card makes an army group of the selected armies without one.
	var cmd: Node = get_first_node_in_group("command_panel")
	panel.select_ids([army.id] as Array[int])
	await process_frame
	var groups_before: int = gs.army_groups.size()
	cmd._on_add_commander()
	_check(gs.army_groups.size() == groups_before + 1 and army.group_id != 0, "the + card forms an army group of the selected army")
