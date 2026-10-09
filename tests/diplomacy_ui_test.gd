extends SceneTree
## Drives the diplomacy UI through the main scene: the panel, the Diplomacy map mode, the peace
## screen, the join prompt and incoming peace offers.
## Run: godot --headless --path . -s res://tests/diplomacy_ui_test.gd

var _failures := 0
var gs: Node
var clock: Node
var main: Node
var D
var Mil


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
	D = load("res://scripts/sim/diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	await _test_panel()
	await _test_map_mode()
	await _test_peace_screen()
	await _test_join_prompt()
	await _test_incoming_offer()
	await _test_nation_menu()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


## A quiet world with the player in France.
func _quiet(player: String) -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player(player)


func _occupy(owner: String, by: String, count: int) -> void:
	var done := 0
	for id: int in gs.nations[owner].provinces:
		if done >= count:
			break
		if id != gs.nations[owner].capital:
			gs.set_controller(id, by)
			done += 1


func _test_panel() -> void:
	_quiet("FRA")
	await process_frame
	var panel: Node = get_first_node_in_group("diplomacy_panel")
	_check(panel != null, "the diplomacy panel exists")
	_check(not panel.visible, "and starts hidden")
	panel.toggle()
	await process_frame
	_check(panel.visible, "it opens")
	_check(panel._list.item_count == 19, "the list shows the other 19 nations (%d)" % panel._list.item_count)
	_check(panel._list.get_item_text(0).contains("Russia") or panel._list.get_item_text(0).contains("Britain") or panel._list.get_item_text(0).contains("United Kingdom"), "the friendliest nation comes first (%s)" % panel._list.get_item_text(0))

	_check(gs.nations["FRA"].diplomacy_points == 50.0, "every nation starts with 50 diplomacy points")
	_check(panel._points.text == "Diplomacy points: 50", "the diplomacy panel shows them (%s)" % panel._points.text)
	var bar: Node = main.get_node("UI/TopBar")
	_check(bar._points.text == "Diplomacy 50", "and so does the top bar (%s)" % bar._points.text)
	gs.nations["FRA"].diplomacy_points = 73.0
	gs.economy_updated.emit()
	panel._refresh()
	await process_frame
	_check(bar._points.text == "Diplomacy 73" and panel._points.text == "Diplomacy points: 73", "both follow the number")
	gs.nations["FRA"].diplomacy_points = 50.0
	gs.economy_updated.emit()
	var ger := 0
	for id: int in gs.nations["GER"].provinces:
		ger = id
		break
	main.map_view.select(ger)
	await process_frame
	_check(panel._selected == "GER", "clicking a German province selects Germany")
	_check(panel._detail.text.contains("German Empire") and panel._detail.text.contains("opinion of you"), "the detail shows its opinion of you (%s)" % panel._detail.text.left(60))
	_check(panel._cb_ids.has("reconquest") and panel._cb_ids.back() == "none", "France can pick reconquest, or no justification")
	_check(not panel._declare.disabled, "and declare with it")
	panel._cb_picker.select(panel._cb_ids.size() - 1)
	panel._refresh_actions()
	_check(panel._declare.disabled and panel._cb_info.text.contains("mobilization"), "a war without a cause is held up until France mobilizes (%s)" % panel._cb_info.text.left(50))
	panel._cb_picker.select(panel._cb_ids.find("reconquest"))
	panel._refresh_actions()
	_check(panel._cb_info.text.contains("-30"), "the price of the casus belli is shown (%s)" % panel._cb_info.text)

	var rus: int = panel._tags.find("RUS")
	panel._list.select(rus)
	panel._selected = "RUS"
	panel._refresh_detail()
	_check(panel._declare.disabled and panel._cb_info.text.contains("allied"), "France cannot declare on its ally Russia")
	_check(panel._treaties.item_count >= 1 and panel._treaties.get_item_text(0).contains("Alliance"), "the treaty with Russia is listed (%s)" % panel._treaties.get_item_text(0))
	_check(not panel._cancel.disabled == false or panel._cancel.disabled, "cancel waits for a selection")
	panel._treaties.select(0)
	panel._refresh_actions()
	_check(not panel._cancel.disabled, "and then can be pressed")

	panel._selected = "GER"
	panel._refresh_detail()
	var before: int = gs.command_log.size()
	panel._on_declare()
	await process_frame
	_check(gs.at_war("FRA", "GER") and gs.command_log.size() == before + 1, "the declare button declares war")
	_check(gs.war_between("FRA", "GER").casus_belli == "reconquest", "with the chosen casus belli")
	_check(panel._peace.visible and not panel._declare.visible, "and the war section switches to peace talks")

	panel._selected = "ESP"
	panel._refresh_detail()
	var cmds: int = gs.command_log.size()
	panel._on_propose("nap")
	_check(gs.command_log.size() == cmds + 1 and panel._status.text != "", "proposing a pact issues a command and reports (%s)" % panel._status.text)
	var treasury: float = gs.nations["FRA"].treasury
	panel._gift_amount.value = 5.0
	panel._on_gift()
	_check(is_equal_approx(gs.nations["FRA"].treasury, treasury - 5.0), "a gift costs the treasury")
	panel.toggle()


func _test_map_mode() -> void:
	_quiet("FRA")
	gs.set_war("FRA", "GER", true)
	var view: Sprite2D = main.map_view
	var Mode = view.get_script().Mode
	view.set_mode(Mode.DIPLOMACY)
	await process_frame
	_check(view.mode == Mode.DIPLOMACY and view.legend().title.contains("France"), "the diplomacy mode has a legend about France")
	_check(view.diplomacy_color("FRA") == view.SELF_COLOR, "France paints itself in its own colour")
	_check(view.diplomacy_color("GER") == view.WAR_COLOR, "an enemy at war is dark red")
	_check(view.diplomacy_color("RUS") == view.ALLY_COLOR, "an ally is teal")
	_check(view.diplomacy_color("GBR") != view.ALLY_COLOR, "an entente partner is not")
	var friendly: Color = view.diplomacy_color("SUI")
	D.set_relation(gs, "FRA", "SUI", 100.0)
	_check(view.diplomacy_color("SUI").g > friendly.g or view.diplomacy_color("SUI") != friendly, "opinion shifts the colour")
	await process_frame
	await process_frame
	var px := Vector2i(gs.nations["GER"].provinces[0] % view.LOOKUP_WIDTH, gs.nations["GER"].provinces[0] / view.LOOKUP_WIDTH)
	_check(_close(view._lookup_image.get_pixelv(px), view.WAR_COLOR), "German ground is painted dark red in the lookup")
	var bel_px := Vector2i(gs.nations["BEL"].provinces[0] % view.LOOKUP_WIDTH, gs.nations["BEL"].provinces[0] / view.LOOKUP_WIDTH)
	_check(view._marks_image.get_pixelv(bel_px).a > 0.5, "Belgium, a guaranteed nation, is hatched")
	_check(view._marks_image.get_pixelv(px).a < 0.5, "Germany is not")
	_check(view._blocs_image.get_pixelv(px).a > 0.5 and view._blocs_image.get_pixelv(px) != view._blocs_image.get_pixelv(Vector2i(gs.nations["FRA"].provinces[0] % view.LOOKUP_WIDTH, gs.nations["FRA"].provinces[0] / view.LOOKUP_WIDTH)), "the two blocs get different outline colours")
	view.set_mode(Mode.POLITICAL)


func _test_peace_screen() -> void:
	_quiet("FRA")
	gs.set_war("FRA", "GER", true)
	_occupy("GER", "FRA", 60)
	var screen: Node = get_first_node_in_group("peace_screen")
	var mil: Node = get_first_node_in_group("military_panel")
	mil.toggle()
	mil._tabs.current_tab = 3
	mil._refresh_wars()
	await process_frame
	_check(mil._peace_button.visible, "the Wars tab offers peace talks for the player's war")
	_check(mil._war_summary.text.contains("War score"), "and shows the war score (%s)" % mil._war_summary.text.get_slice("\n", 3))
	var war: Object = gs.war_between("FRA", "GER")
	screen.open_war(war.id)
	await process_frame
	_check(screen.visible and screen._title.text.contains("France") and screen._title.text.contains("German"), "the peace screen opens (%s)" % screen._title.text)
	_check(screen._provinces.item_count == gs.nations["GER"].provinces.size(), "it lists the enemy's provinces")
	_check(screen._provinces.get_item_text(0).contains("held by"), "ground France holds comes first")
	_check(screen._propose.disabled == false, "a white peace can be proposed straight away")
	screen._select_held()
	_check(screen._cost_bar.value > 0.0 and screen._cost_label.text.contains("Terms cost"), "choosing provinces shows their cost (%s)" % screen._cost_label.text.left(40))
	_check(not screen._propose.disabled, "within the score")
	screen._indemnity.button_pressed = true
	screen._share.value = 50.0
	screen._months.value = 60.0
	screen._refresh_cost()
	_check(screen._propose.disabled and screen._cost_label.text.contains("does not pay"), "an indemnity too big for the score is refused (%s)" % screen._cost_label.text.right(60))
	screen._indemnity.button_pressed = false
	screen._refresh_cost()
	screen._mode.select(1)
	screen._rebuild_terms()
	_check(screen._provinces.item_count == gs.nations["FRA"].provinces.size(), "offering terms lists France's own provinces")
	screen._mode.select(0)
	screen._rebuild_terms()
	screen._select_held()
	var before: int = gs.command_log.size()
	screen._on_propose()
	await process_frame
	_check(gs.command_log.size() == before + 1 and not gs.at_war("FRA", "GER"), "proposing the terms ends the war (Germany, far behind, accepts)")
	_check(not screen.visible, "and the screen closes")
	_check(gs.war_history.back().peace.taker == "FRA", "the war records France as the taker")
	mil.toggle()


func _test_join_prompt() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	var prompt: Node = get_first_node_in_group("join_prompt")
	await process_frame
	_check(not prompt.visible, "the join prompt is hidden at the start")
	for i in 80:
		if not gs.pending_joins.is_empty():
			break
		clock.advance_day()
	await process_frame
	_check(prompt.visible and gs.pending_joins.size() == 1, "when Russia enters the war, France is asked")
	_check(prompt._title.text.contains("Russia") and prompt._why.text.contains("alliance") or prompt._why.text.contains("Russia"), "the prompt names the ally (%s)" % prompt._title.text)
	_check(prompt._join_text.text.contains("War with") and prompt._stay_text.text.contains("opinion"), "and the price of each answer")
	clock.paused = false
	_check(clock.paused, "time is held")
	var feed: Node = get_first_node_in_group("event_feed")
	_check(feed.get_child_count() > 0, "the event feed reported the crisis (%d lines)" % feed.get_child_count())
	prompt._answer(true)
	await process_frame
	_check(gs.at_war("FRA", "GER") or gs.at_war("FRA", "AUH"), "joining puts France at war")
	_check(not prompt.visible or not gs.pending_joins.is_empty(), "and the prompt closes unless another decision waits")
	# Decline path.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	for i in 80:
		if not gs.pending_joins.is_empty():
			break
		clock.advance_day()
	await process_frame
	var rel: float = D.relation(gs, "FRA", "RUS")
	prompt._answer(false)
	await process_frame
	_check(D.relation(gs, "FRA", "RUS") < rel and not gs.at_war("FRA", "AUH") , "staying out costs Russia's goodwill and keeps France out")
	clock.paused = true


func _test_incoming_offer() -> void:
	_quiet("FRA")
	gs.set_war("FRA", "GER", true)
	_occupy("GER", "FRA", 200)
	var screen: Node = get_first_node_in_group("peace_screen")
	D.step_month(gs)
	await process_frame
	_check(gs.pending_offers.size() == 1 and screen.visible, "a losing AI's offer opens the peace screen")
	_check(screen._title.text.contains("German") and screen._incoming_text.text.contains("give you"), "which says what Germany offers (%s)" % screen._incoming_text.text.left(70))
	_check(screen._accept.is_visible_in_tree() and not screen._propose.is_visible_in_tree(), "with Accept and Refuse")
	clock.paused = false
	_check(clock.paused, "time is held")
	screen._answer(true)
	await process_frame
	_check(not gs.at_war("FRA", "GER") and not screen.visible and gs.pending_offers.is_empty(), "accepting ends the war and closes the screen")
	clock.paused = true


func _test_nation_menu() -> void:
	_quiet("FRA")
	var menu: Node = get_first_node_in_group("nation_menu")
	var mil: Node = get_first_node_in_group("military_panel")
	mil.clear_selection()
	_check(menu != null and not menu.visible, "the nation menu exists and starts closed")
	var ger: int = gs.nations["GER"].provinces[0]
	var fra: int = gs.nations["FRA"].provinces[0]
	main.map_view.province_ordered.emit(fra)
	await process_frame
	_check(not menu.visible, "right-clicking your own land opens nothing")
	main.map_view.province_ordered.emit(ger)
	await process_frame
	await process_frame
	_check(menu.visible and menu._tag == "GER", "right-clicking German land opens Germany's menu")
	_check(menu._name.text == "German Empire" and menu._flag.tag == "GER", "with its name and flag")
	_check(menu._actions.text.contains("diplomacy points: 50"), "and your diplomacy points above the actions (%s)" % menu._actions.text)
	_check(menu._lines.text.contains("Troops:") and menu._lines.text.contains("under arms"), "its troops (%s)" % menu._lines.text.get_slice("
", 1))
	_check(menu._lines.text.contains("Alliances: ") and menu._lines.text.contains("Austria-Hungary"), "its alliances")
	_check(menu._lines.text.contains("At war with: nobody"), "and wars")
	_check(menu._cb_ids.has("reconquest") and menu._declare.is_visible_in_tree(), "the actions include declaring war with a casus belli")
	_check(menu.get_global_rect().position.x >= 0.0 and menu.get_global_rect().end.x <= root.get_visible_rect().size.x + 1.0, "and it stays on screen")
	var flag_size: Vector2 = menu._flag.size
	_check(flag_size.x > 30.0 and flag_size.y > 20.0, "the flag has room (%s)" % str(flag_size))
	var before: int = gs.command_log.size()
	menu._on_declare()
	await process_frame
	_check(gs.at_war("FRA", "GER") and gs.command_log.size() == before + 1, "declaring war from the menu works")
	await process_frame
	_check(menu._lines.text.contains("At war with: YOU") and menu._peace.is_visible_in_tree() and not menu._war_row.is_visible_in_tree(), "and the menu now offers peace talks")
	menu.close()
	_check(not menu.visible, "it closes")

	# A friendly nation shows its ties, and a treaty can be cancelled from the menu.
	main.map_view.province_ordered.emit(gs.nations["RUS"].provinces[0])
	await process_frame
	_check(menu._tag == "RUS" and menu._lines.text.contains("France"), "Russia's menu lists France among its alliances")
	_check(menu._cancel_box.get_child_count() >= 1, "with a button to cancel the alliance")
	menu.close()

	# With armies selected a right click is an order, not a menu; Shift forces the menu.
	_quiet("FRA")
	var army_province := 0
	for a in Mil.armies_of(gs, "FRA"):
		army_province = a.province
		break
	mil.toggle()
	main.map_view.select(army_province)
	await process_frame
	_check(mil.has_selection(), "France's armies are selected")
	var orders: int = gs.command_log.size()
	var target := 0
	for n in Mil.neighbors(army_province):
		if gs.province_owner[n] == "FRA":
			target = n
	main.map_view.province_ordered.emit(target)
	await process_frame
	_check(gs.command_log.size() == orders + 1 and not menu.visible, "right-clicking with armies selected gives the order")
	mil.clear_selection()
	mil.toggle()
