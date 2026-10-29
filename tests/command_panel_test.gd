extends SceneTree
## Drives the command panel through the main scene: its army and fleet cards, groups that fold to
## their marshal, the show/hide toggle, and the orders strip (merge, split, detach, halt,
## symbol, deselect, fleet orders).
## Run: godot --headless --path . -s res://tests/command_panel_test.gd

var _failures := 0
var CommandCardC
var CreateGroupC
var SetMarshalC


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
	load("res://scripts/ui/ui_settings.gd").command_open = true  # it starts closed; these tests use it open
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	CommandCardC = load("res://scripts/ui/command_card.gd")
	CreateGroupC = load("res://scripts/sim/create_army_group.gd")
	SetMarshalC = load("res://scripts/sim/set_marshal.gd")
	var Mil = load("res://scripts/sim/military.gd")
	var panel: Node = get_first_node_in_group("military_panel")
	var bar: Node = get_first_node_in_group("command_panel")
	_check(bar != null, "the command panel exists")
	var Settings = load("res://scripts/ui/ui_settings.gd")
	gs.set_player("FRA")
	await process_frame
	_check(not bar.visible, "it does not show while a nation is being picked")
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	gs.set_player("FRA")
	await process_frame
	_check(bar.visible and not bar._army_orders.visible and not bar._top.visible, "it shows with no selection, with no row of orders")
	_check(bar._title.text.contains("armies"), "and totals the armies (%s)" % bar._title.text)

	var nancy := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Meurthe-et-Moselle":
			nancy = id
	main.map_view.select(nancy)
	await process_frame
	_check(bar._plans_bar.visible and not bar._army_orders.visible and bar._ids == panel._selected, "selecting an army: the Battle Plans toolbar acts on it; no row of orders")
	bar._on_card_context(Vector2(300, 300), "army", panel._selected[0])
	var texts: Array = []
	for i in bar._menu.item_count:
		texts.append(bar._menu.get_item_text(i))
	_check(texts.has("Merge the selected armies") and texts.has("Split in two") and texts.has("Halt the march") and texts.has("Send home") and texts.any(func(t: String) -> bool: return t.begins_with("Detach one")), "its card's right click menu gives the orders: merge, split, halt, detach, send home... (%d items)" % texts.size())
	bar._menu.hide()
	_check(bar._title.text.contains("men") and bar._title.text.contains("Meurthe-et-Moselle"), "and names the army (%s)" % bar._title.text)
	_check(bar._merge.disabled and not bar._split.disabled and not bar._detach.disabled, "one army can be split or detached from, not merged")
	_check(bar._halt.disabled, "and it is not marching, so there is nothing to halt")
	var rect: Rect2 = bar.get_global_rect()
	var palette: Control = get_first_node_in_group("map_modes")
	await process_frame
	rect = bar.get_global_rect()
	var view0: Vector2 = root.get_visible_rect().size
	_check(rect.end.y >= view0.y - 12.0 and rect.position.x >= 0.0 and not rect.intersects(palette.get_global_rect()), "it sits on the bottom edge, clear of the map modes (y %d of %d)" % [rect.end.y, view0.y])
	_check(palette.get_global_rect().end.x >= view0.x - 16.0 and palette.get_global_rect().end.y >= view0.y - 16.0 and palette._drop.is_visible_in_tree() and not palette._list_panel.visible, "the map modes are a drop-down in the bottom right corner")
	_check(absf(rect.get_center().x - view0.x * 0.5) < 2.0, "it stands in the middle of the screen (%d of %d)" % [rect.get_center().x, view0.x])

	# Split in half, then merge back.
	var army = gs.armies[panel._selected[0]]
	var units: int = army.units.size()
	bar._on_split()
	await process_frame
	_check(panel._selected.size() == 2 and army.units.size() < units, "Split divides the army and selects both halves")
	_check(bar._ids == panel._selected and not bar._merge.disabled, "the bar follows, and now Merge is open")
	bar._on_merge()
	await process_frame
	_check(panel._selected.size() == 1 and gs.armies[panel._selected[0]].units.size() == units, "Merge puts them together again")
	# Detach one type.
	army = gs.armies[panel._selected[0]]
	bar._fill_detach()
	var popup: PopupMenu = bar._detach.get_popup()
	_check(popup.item_count >= 1 and popup.get_item_text(0).contains("(of "), "Detach lists the unit types of the army (%s)" % popup.get_item_text(0))
	bar._on_detach(0)
	await process_frame
	_check(panel._selected.size() == 2, "Detach splits one unit off")
	bar._on_merge()
	await process_frame

	# The Battle Plans toolbar stands over the orders (its tools are tested in battle_plan_toolbar_test).
	_check(bar._plans_bar.visible and bar._plans_bar.roots().size() == 1, "the Battle Plans toolbar shows, acting on the selected army")
	gs.set_war("FRA", "GER", true)

	# March and halt.
	var dest := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "FRA":
			dest = n
	panel.order_move(dest)
	await process_frame
	_check(not bar._halt.disabled, "a marching army can be halted")
	bar._on_halt()
	await process_frame
	var marching = gs.armies[panel._selected[0]]
	_check(marching.path.is_empty() and bar._halt.disabled, "Halt stops it")

	# Symbol.
	bar._fill_symbols()
	bar._on_symbol(bar._symbol_ids.find("guard"))
	_check(gs.armies[panel._selected[0]].icon == "guard", "Symbol changes the marker")

	# Several armies at once, and deselect.
	main.map_view.select(nancy)
	panel.select_in_rect(Rect2(Vector2.ZERO, Vector2(100000, 100000)))
	await process_frame
	_check(bar._plans_bar.visible and panel._selected.size() > 3 and bar._title.text.contains("armies"), "a box selection shows the total (%s)" % bar._title.text)
	_check(bar._merge.disabled, "armies in different provinces cannot merge")
	bar._deselect.pressed.emit()
	await process_frame
	_check(not bar._army_orders.visible and panel._selected.is_empty(), "Deselect clears the selection")

	await _test_cards(bar, panel, gs)
	await _test_toggle(bar, Settings)
	await _test_divisions(bar, panel, gs)
	await _test_fleets(bar, gs)

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _cards(bar: Node) -> Array:
	return bar._cards.find_children("*", "CommandCard", true, false)


func _by_title(bar: Node, title: String):
	for c in _cards(bar):
		if c.title == title:
			return c
	return null


func _test_cards(bar: Node, panel: Node, gs: Node) -> void:
	gs.set_player("FRA")
	await process_frame
	var mine: Array = []
	for a in gs.armies.values():
		if a.tag == "FRA":
			mine.append(a)
	mine.sort_custom(func(x, y) -> bool: return x.id < y.id)
	_check(mine.size() >= 4, "France has armies to arrange (%d)" % mine.size())
	var loose := _cards(bar).filter(func(c) -> bool: return c.title != "New group")
	_check(loose.size() == mine.size(), "with no groups there is a card for each army (%d)" % loose.size())
	var led = mine.filter(func(a) -> bool: return a.general_id != 0)
	var first = led[0]
	var card = _by_title(bar, first.display_name)
	_check(card.badge == CommandCardC.initials(first.general_name) and card.skill == "%.2f" % first.general_skill and not card.empty, "an army's card carries its general's initials and skill (%s %s)" % [card.badge, card.skill])
	var bare = mine.filter(func(a) -> bool: return a.general_id == 0)
	_check(card.portrait != null and card.portrait == load("res://scripts/ui/portraits.gd").for_name(first.general_name), "and his portrait, the same one each time for his name")
	if not bare.is_empty():
		_check(_by_title(bar, bare[0].display_name).empty and _by_title(bar, bare[0].display_name).portrait == null, "an army without a general shows an empty slot, no portrait")

	# Clicking a card selects the army; Shift adds another.
	card.pressed.emit(false)
	await process_frame
	var one: Array[int] = [first.id]
	_check(panel._selected == one and bar._ids == one, "clicking a card selects that army")
	_check(_by_title(bar, first.display_name).selected, "and the card is marked selected")
	var second = mine[1] if mine[1] != first else mine[0]
	_by_title(bar, second.display_name).pressed.emit(true)
	await process_frame
	_check(panel._selected.size() == 2, "Shift adds a second army to the selection")

	# A group of three armies with a marshal over it.
	var ids: Array[int] = [mine[0].id, mine[1].id, mine[2].id]
	var made = CreateGroupC.new("FRA", "Test Group", ids)
	_check(gs.issue(made), "a group of three armies is made")
	# Every French general leads an army at the start, so a new one will be the marshal.
	load("res://scripts/sim/military.gd").new_general(gs, "FRA", "Maurice Sarrail", 1.1)
	var free: Array = _pool(gs, "FRA")
	_check(not free.is_empty(), "France has a free general for the marshal")
	_check(gs.issue(SetMarshalC.new("FRA", made.group_id, free[0].id)), "a marshal is appointed")
	await process_frame
	var marshals := _cards(bar).filter(func(c) -> bool: return c.marshal)
	_check(marshals.size() == 1 and marshals[0].badge == CommandCardC.initials(free[0].display_name), "the group's block opens with a gold marshal card")
	var total_before := _cards(bar).size()
	_check(marshals[0].title == "Test Group" and marshals[0].line1 == "3 armies", "the marshal's card names the group and counts its armies (%s, %s)" % [marshals[0].title, marshals[0].line1])

	# Fold it down to the marshal.
	bar._on_fold(made.group_id)
	await process_frame
	_check(_cards(bar).size() == total_before - 3, "folding the group hides its armies and leaves the marshal (%d to %d)" % [total_before, _cards(bar).size()])
	_check(_cards(bar).filter(func(c) -> bool: return c.marshal).size() == 1, "the marshal card stays")
	bar._on_card_context(Vector2(300, 300), "marshal", made.group_id)
	_check(bar._menu_calls.size() >= 2 and bar._menu.get_item_text(bar._menu.get_item_index(bar._menu_calls.size() - 2)).begins_with("Open the group"), "the marshal's right click menu offers to open it again")
	_cards(bar).filter(func(c) -> bool: return c.marshal)[0].pressed.emit(false)
	await process_frame
	_check(panel._selected.size() == 3 and panel._selected.has(mine[0].id), "clicking the folded marshal selects every army of the group")
	_check(bar._attack.visible, "and the Attack order is offered for the group")
	bar._on_fold(made.group_id)
	await process_frame
	_check(_cards(bar).size() == total_before, "opening the header brings the armies back")

	# Right click menus.
	bar._on_card_context(Vector2(300, 300), "army", mine[3].id)
	_check(bar._menu_calls.size() >= 2, "right clicking an army offers generals and groups (%d choices)" % bar._menu_calls.size())
	bar._on_card_context(Vector2(300, 300), "marshal", made.group_id)
	_check(bar._menu_calls.size() >= 2, "right clicking the marshal offers the pool and Disband")
	bar._menu_calls[bar._menu_calls.size() - 1].call()
	await process_frame
	_check(not gs.army_groups.has(made.group_id), "Disband dissolves the group")
	panel.clear_selection()


func _pool(gs: Node, tag: String) -> Array:
	return load("res://scripts/sim/military.gd").pool_of(gs, tag)


func _test_toggle(bar: Node, Settings) -> void:
	_check(bar.is_open() and bar._scroll.visible, "the panel starts open")
	var open_height: float = bar.size.y
	bar.toggle()
	await process_frame
	await process_frame
	_check(not bar.is_open() and not bar._scroll.visible and bar.visible, "the toggle hides the cards but leaves the toggle")
	_check(bar.size.y < open_height and not Settings.command_open, "it gets shorter and the choice is kept (%d to %d)" % [open_height, bar.size.y])
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.pressed = true
	bar._unhandled_key_input(key)
	await process_frame
	_check(bar.is_open() and bar._scroll.visible and Settings.command_open, "the C key opens it again")
	var palette: Control = get_first_node_in_group("map_modes")
	_check(not bar.get_global_rect().intersects(palette.get_global_rect()) and bar.get_global_rect().end.x <= root.get_visible_rect().size.x, "it keeps clear of the map modes and inside the screen")
	var view: Vector2 = root.get_visible_rect().size
	var middle: float = bar.get_global_rect().get_center().x
	_check(middle > view.x * 0.3 and middle < view.x * 0.7 and bar.get_global_rect().size.y < view.y * 0.35, "it stands in the lower middle of the screen and takes under a third of its height (centre %d of %d, %d high)" % [middle, view.x, bar.get_global_rect().size.y])
	_check(bar._command_frame.get_global_rect().encloses(bar._plans_bar.get_global_rect()) and bar._command_frame.get_global_rect().end.y <= bar._scroll.get_global_rect().position.y, "one framed row (Battle Plans) over the cards")


func _test_fleets(bar: Node, gs: Node) -> void:
	gs.set_player("GBR")
	await process_frame
	var navy: Node = get_first_node_in_group("navy_panel")
	var mine: Array = []
	for f in gs.fleets.values():
		if f.tag == "GBR":
			mine.append(f)
	var grand = mine.filter(func(f) -> bool: return f.display_name == "Grand Fleet")[0]
	_check(bar._mode == "army", "the panel shows armies until a fleet is picked")
	var ids: Array[int] = [grand.id]
	navy.select_fleets(ids)
	await process_frame
	_check(bar._mode == "navy" and bar._fleet_orders.visible and not bar._army_orders.visible, "selecting a fleet shows the fleets alone with the fleet orders")
	var cards := _cards(bar)
	_check(cards.size() == mine.size() and cards.all(func(c) -> bool: return c.title != "New group"), "there is a card for each fleet and nothing else (%d)" % cards.size())
	var card = _by_title(bar, "Grand Fleet")
	_check(card.selected and card.badge == str(grand.ships.size()), "the selected fleet's card shows its ships (%s)" % card.badge)
	_check(bar._title.text.contains("Grand Fleet") and bar._f_merge.disabled and not bar._f_detach.disabled, "the title names it; one fleet can be detached from, not merged")

	bar._fill_orders()
	var missions: Array = load("res://scripts/sim/navy.gd").cfg.missions.keys()
	_check(bar._f_orders.get_popup().item_count == missions.size(), "Orders lists every standing order")
	var other: String = "patrol" if grand.mission != "patrol" else "blockade"
	bar._on_orders(missions.find(other))
	_check(grand.mission == other, "choosing an order sets it (%s)" % other)

	var ships: int = grand.ships.size()
	bar._fill_fleet_detach()
	bar._on_fleet_detach(0)
	await process_frame
	_check(grand.ships.size() == ships - 1 and navy._selected.size() == 1 and navy._selected[0] != grand.id, "Detach splits a squadron off and selects it")
	var both: Array[int] = [grand.id, navy._selected[0]]
	navy.select_ids(both)
	await process_frame
	_check(bar._fleet_ids == both and not bar._f_merge.disabled, "a bigger selection opens Merge")
	bar._on_fleet_merge()
	await process_frame
	_check(grand.ships.size() == ships, "Merge puts the fleet together again")

	var other_fleet = mine.filter(func(f) -> bool: return f != grand)[0]
	_by_title(bar, other_fleet.display_name).pressed.emit(false)
	await process_frame
	var just_other: Array[int] = [other_fleet.id]
	_check(navy._selected == just_other, "clicking a fleet's card selects that fleet")
	bar._f_deselect.pressed.emit()
	await process_frame
	_check(not bar._fleet_orders.visible and navy._selected.is_empty(), "Deselect clears the fleet selection")
	_check(bar._mode == "army" and bar._add_group.visible and bar._add_army.visible, "and the armies come back, with a + card at each end")


func _test_divisions(bar: Node, panel: Node, gs: Node) -> void:
	gs.set_player("FRA")
	await process_frame
	var a = null
	for x in gs.armies.values():
		if x.tag == "FRA" and x.units.size() >= 6:
			a = x
			break
	var split_ids: Array[int] = [1, 3]
	var made = load("res://scripts/sim/split_army.gd").new("FRA", a.id, split_ids)
	_check(gs.issue(made), "a second army is split off in the same province")
	var b = gs.armies[made.new_army_id]
	var one: Array[int] = [a.id]
	panel.select_ids(one)
	await process_frame
	bar._on_card_context(Vector2(300, 300), "army", a.id)
	var pick_index := -1
	for i in bar._menu.item_count:
		if bar._menu.get_item_text(i).begins_with("Pick divisions"):
			pick_index = i
	bar._menu_calls[bar._menu.get_item_id(pick_index)].call()
	bar._menu.hide()
	await process_frame
	_check(bar._div_row.visible, "Pick divisions in the card's menu shows its divisions row")
	var chips: Array = bar._div_row.find_children("*", "Button", true, false).filter(func(c) -> bool: return c.toggle_mode)
	_check(chips.size() == a.units.size(), "with a chip for each division (%d)" % chips.size())
	_check(bar._div_new.disabled, "New army waits for a pick")
	chips[0].button_pressed = true
	chips[2].button_pressed = true
	await process_frame
	var pair_sel: Array[int] = [0, 2]
	_check(bar._div_sel == pair_sel and not bar._div_new.disabled, "picking chips selects those divisions")
	var moved: Array = [a.units[0], a.units[2]]
	var before_a: int = a.units.size()
	var before_b: int = b.units.size()
	bar._on_card_context(Vector2(300, 300), "army", b.id)
	_check(bar._menu_calls.size() >= 2, "right clicking another army's card offers the move")
	bar._menu_calls[0].call()
	await process_frame
	_check(a.units.size() == before_a - 2 and b.units.size() == before_b + 2 and b.units.has(moved[0]) and b.units.has(moved[1]), "the picked divisions move to that army")
	var just_b: Array[int] = [b.id]
	_check(bar._div_sel.is_empty() and bar._ids == just_b, "the pick is cleared and the new army is selected")

	# An army elsewhere cannot take them, and the menu says why.
	var far = null
	for x in gs.armies.values():
		if x.tag == "FRA" and x.province != a.province:
			far = x
			break
	panel.select_ids(one)
	await process_frame
	bar._div_row.find_children("*", "Button", true, false).filter(func(c) -> bool: return c.toggle_mode)[0].button_pressed = true
	await process_frame
	var count: int = a.units.size()
	bar._on_card_context(Vector2(300, 300), "army", far.id)
	bar._menu_calls[0].call()
	await process_frame
	_check(a.units.size() == count, "units cannot move to an army in another province")
	_check(bar._menu.get_item_text(bar._menu.get_item_index(0)).contains("not in the same province"), "and the menu gives the reason")

	# New army from the pick.
	panel.select_ids(one)
	await process_frame
	bar._div_row.find_children("*", "Button", true, false).filter(func(c) -> bool: return c.toggle_mode)[1].button_pressed = true
	await process_frame
	var armies_before: int = gs.armies.size()
	bar._on_division_new()
	await process_frame
	_check(gs.armies.size() == armies_before + 1 and a.units.size() == count - 1, "New army makes an army of the picked divisions")
	panel.clear_selection()
