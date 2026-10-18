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
	await _test_perspective()
	await _test_points_ui()

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
	_check(panel._points.text.begins_with("Diplomacy points: 50 (+") and panel._points.text.ends_with("a month)"), "the diplomacy panel shows them with the monthly income (%s)" % panel._points.text)
	var bar: Node = main.get_node("UI/TopBar")
	_check(bar._points.text == "Diplomacy 50", "and so does the top bar (%s)" % bar._points.text)
	gs.nations["FRA"].diplomacy_points = 73.0
	gs.economy_updated.emit()
	panel._refresh()
	await process_frame
	_check(bar._points.text == "Diplomacy 73" and panel._points.text.begins_with("Diplomacy points: 73"), "both follow the number")
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
	# Costs in diplomacy points are on the buttons, and a poor nation cannot press them.
	panel._selected = "ITA"
	panel._refresh_detail()
	_check(panel._propose_buttons["alliance"].text == "Alliance (40)" and panel._propose_buttons["nap"].text == "Non-aggression (15)", "the treaty buttons show their cost in points")
	_check(panel._gift.text == "Send gift (5 points)", "so does the gift (%s)" % panel._gift.text)
	panel._selected = "GER"
	panel._refresh_detail()
	_check(panel._declare.text.begins_with("Declare war ("), "and declaring war (%s)" % panel._declare.text)
	gs.nations["FRA"].diplomacy_points = 4.0
	panel._refresh()
	panel._selected = "ITA"
	panel._refresh_detail()
	_check(panel._propose_buttons["alliance"].disabled and panel._propose_buttons["alliance"].tooltip_text.contains("Not enough diplomacy points"), "with 4 points the buttons are off, and say why")
	_check(panel._gift.disabled, "and the gift")
	gs.nations["FRA"].diplomacy_points = 50.0
	panel._refresh()
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
	mil._tabs.current_tab = 1
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
	var panel: Node = get_first_node_in_group("nation_stats")
	var mil: Node = get_first_node_in_group("military_panel")
	mil.clear_selection()
	panel.close_window()
	_check(panel != null and not panel.visible, "the country panel exists and starts closed")
	var ger: int = gs.nations["GER"].provinces[0]
	var fra: int = gs.nations["FRA"].provinces[0]
	main.map_view.province_ordered.emit(ger)
	await process_frame
	await process_frame
	_check(panel.visible and panel.shown_tag() == "GER", "right-clicking German land opens the country panel on Germany")
	_check(panel.position.x < 20.0 and panel.position.y >= 40.0 and panel.size.y > 380.0, "docked on the left of the screen, tall (%s, %s)" % [str(panel.position), str(panel.size)])
	_check(panel._name.text == "German Empire" and panel._flag.tag == "GER", "with its name and flag")
	_check(panel._actions_box.is_visible_in_tree() and panel._declare.is_visible_in_tree(), "and the actions you can take: declaring war")
	_check(panel._cb_ids.has("reconquest"), "with a casus belli to pick")
	var before: int = gs.command_log.size()
	panel._on_declare()
	await process_frame
	await process_frame
	_check(gs.at_war("FRA", "GER") and gs.command_log.size() == before + 1, "declaring war from the panel works")
	_check(panel._peace.is_visible_in_tree() and not panel._war_row.is_visible_in_tree(), "and the panel then offers peace talks")

	# Right-clicking another nation changes the panel to it.
	main.map_view.province_ordered.emit(gs.nations["RUS"].provinces[0])
	await process_frame
	await process_frame
	_check(panel.shown_tag() == "RUS" and panel._name.text == "Russian Empire", "right-clicking Russia changes the panel to Russia")
	_check(panel._cancel_box.get_child_count() >= 1, "with a button to cancel the alliance with France")
	# Your own nation: figures, no actions.
	main.map_view.province_ordered.emit(fra)
	await process_frame
	await process_frame
	_check(panel.shown_tag() == "FRA" and not panel._actions_box.visible, "right-clicking your own land shows your own nation, without actions")
	panel.close_window()
	_check(not panel.visible, "the X closes it")
	panel.show_nation("ITA")
	await process_frame
	_check(panel.visible and panel.position.x < 20.0 and panel.shown_tag() == "ITA", "it opens in the same place again")

	# With armies selected a right click is an order, not a nation.
	_quiet("FRA")
	panel.close_window()
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
	_check(gs.command_log.size() == orders + 1 and not panel.visible, "right-clicking with armies selected gives the order and shows no panel")
	mil.clear_selection()
	mil.toggle()


func _test_perspective() -> void:
	_quiet("FRA")
	gs.set_war("FRA", "GER", true)
	var view: Sprite2D = main.map_view
	var Mode = view.get_script().Mode
	var menu: Node = get_first_node_in_group("nation_stats")
	var palette: Node = null
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "map_modes" in c.get_script().resource_path:
			palette = c
	menu.close_window()
	view.set_mode(Mode.DIPLOMACY)
	await process_frame
	var ger: int = gs.nations["GER"].provinces[0]
	var fra: int = gs.nations["FRA"].provinces[0]
	_check(view.diplomacy_viewpoint() == "FRA", "the Diplomacy map starts from the player's point of view")
	view.province_ordered.emit(ger)
	await process_frame
	await process_frame
	_check(view.diplomacy_viewpoint() == "GER", "right-clicking Germany in the Diplomacy mode moves the point of view to Germany")
	_check(menu.visible and menu.shown_tag() == "GER", "and the country panel changes to Germany as well")
	_check(view.diplomacy_color("GER") == view.SELF_COLOR, "Germany is painted as the viewer")
	_check(view.diplomacy_color("FRA") == view.WAR_COLOR, "France is its enemy at war")
	_check(view.diplomacy_color("AUH") == view.ALLY_COLOR, "Austria-Hungary its ally")
	var rus: Color = view.diplomacy_color("RUS")
	_check(rus.r > rus.g, "and Russia, which Germany dislikes, is on the hostile side of the scale")
	_check(view.legend().title.contains("German"), "the legend names Germany (%s)" % view.legend().title)
	_check(palette._view_label.visible and palette._view_label.text.contains("German") and palette._view_back.text.contains("France"), "the palette says whose view it is and offers the way back")

	var dip: Node = get_first_node_in_group("diplomacy_panel")
	dip.toggle()
	await process_frame
	await process_frame
	_check(dip._perspective_row.visible and dip._perspective.text.contains("German"), "the Diplomacy window says it is seen from Germany")
	_check("GER" not in dip._tags and "FRA" in dip._tags, "it lists everyone but Germany, France included")
	_check(dip._list.get_item_text(0).contains("Austria-Hungary") and dip._list.get_item_text(0).contains("ally"), "Germany's closest friend first (%s)" % dip._list.get_item_text(0))
	_check(not dip._declare.is_visible_in_tree() and not dip._propose_buttons["alliance"].is_visible_in_tree() and not dip._gift.is_visible_in_tree(), "there are no actions: they are not France's to take")
	_check(dip._treaties.is_visible_in_tree(), "but the treaties are shown")
	dip._back.pressed.emit()
	await process_frame
	await process_frame
	_check(view.diplomacy_viewpoint() == "FRA" and not dip._perspective_row.visible and dip._declare.is_visible_in_tree() or dip._peace.is_visible_in_tree(), "Back returns to France's view, with its actions")
	dip.close_window()

	view.province_ordered.emit(ger)
	await process_frame
	view.province_ordered.emit(fra)
	await process_frame
	_check(view.diplomacy_viewpoint() == "FRA" and view.viewpoint == "", "right-clicking your own nation returns to your view")
	view.province_ordered.emit(ger)
	await process_frame
	view.set_mode(Mode.POLITICAL)
	await process_frame
	_check(view.viewpoint == "" and not palette._view_label.visible, "leaving the Diplomacy mode drops the borrowed point of view")
	view.province_ordered.emit(ger)
	await process_frame
	_check(not menu.visible, "right-clicking the nation on show again closes the country panel, whatever the mode")
	view.province_ordered.emit(ger)
	await process_frame
	_check(menu.visible and menu.shown_tag() == "GER", "and the next right click shows the nation in the country panel again")
	menu.close_window()
	gs.set_war("FRA", "GER", false)


func Diplomacy_income(tag: String) -> float:
	return D.point_income(gs, tag)


func _test_points_ui() -> void:
	_quiet("FRA")
	var panel: Node = get_first_node_in_group("diplomacy_panel")
	var stats: Node = get_first_node_in_group("nation_stats")
	var eco: Node = get_first_node_in_group("economy_panel")
	var bar: Node = main.get_node("UI/TopBar")
	panel.toggle()
	await process_frame
	await process_frame
	panel._selected = "ITA"
	panel._refresh_detail()
	await process_frame

	# Buying points.
	_check(panel._buy.visible and panel._buy.text == "Buy 10 points (£3.0M)", "the Diplomacy window offers to buy points (%s)" % panel._buy.text)
	var money: float = gs.nations["FRA"].treasury
	panel._on_buy()
	await process_frame
	await process_frame
	_check(gs.nations["FRA"].diplomacy_points == 60.0 and is_equal_approx(gs.nations["FRA"].treasury, money - 3.0), "buying gives ten points for £3M")
	_check(panel._buy.text == "Buy 10 points (£3.8M)" and bar._points.text == "Diplomacy 60", "the price rises, and the top bar follows (%s)" % panel._buy.text)
	gs.nations["FRA"].diplomacy_points = 200.0
	panel._refresh()
	_check(panel._buy.disabled and panel._buy.tooltip_text.contains("full"), "a full stock switches the button off")
	gs.nations["FRA"].diplomacy_points = 50.0
	panel._refresh()

	# Improving relations.
	_check(panel._improve.text == "Improve relations (10)" and not panel._improve.disabled, "the window has an Improve relations button with its cost (%s)" % panel._improve.text)
	_check(panel._improve.tooltip_text.contains("year"), "and says what it does")
	panel._on_improve()
	await process_frame
	await process_frame
	_check(gs.relation_projects.size() == 1 and gs.nations["FRA"].diplomacy_points == 40.0, "pressing it starts an effort and spends 10 points")
	_check(panel._improve.text == "Improving… (12 months left)" and panel._improve.disabled, "the button shows it under way")
	_check(panel._projects.visible and panel._projects.text.contains("Italy"), "and the efforts are listed (%s)" % panel._projects.text)
	_check(panel._detail.text.contains("improving relations: 12 months"), "and in the nation's details")
	panel.close_window()

	# The country panel has the same.
	stats.show_nation("ESP")
	await process_frame
	await process_frame
	_check(stats._improve.is_visible_in_tree() and stats._improve.text == "Improve relations (10)", "the country panel has the button too")
	_check(stats._relation_label.is_visible_in_tree() and stats._relation_label.text.begins_with("Relations: +10  Neutral"), "with the relations beside it (%s)" % stats._relation_label.text.replace("\n", " / "))
	_check(stats._relation_bar.is_visible_in_tree() and is_equal_approx(stats._bar_value, 10.0) and is_equal_approx(stats._bar_base, 10.0), "and a gauge of them")
	stats._on_improve()
	await process_frame
	_check(gs.relation_projects.size() == 2 and stats._improve.disabled, "pressing it there works")
	_check(stats._relation_label.text.contains("improving by 3 a month, 12 months left"), "and the relations say the effort is under way (%s)" % stats._relation_label.text.replace("\n", " / "))
	stats.show_nation("SUI")
	D.set_relation(gs, "FRA", "SUI", -70.0)
	stats._refresh()
	_check(stats._relation_label.text.begins_with("Relations: -70  Hostile") and stats._relation_label.text.contains("settling up toward +0"), "a low opinion is called hostile and shown settling back (%s)" % stats._relation_label.text.replace("\n", " / "))
	D.set_relation(gs, "FRA", "SUI", 0.0)
	gs.set_war("FRA", "ITA", true)
	stats.show_nation("ITA")
	_check(stats._relation_label.text.contains("at war"), "and a war is noted")
	gs.set_war("FRA", "ITA", false)
	stats.show_nation("ESP")
	stats.close_window()

	# Income sources in the top bar and the Economy window.
	var tip: String = bar._chips["points"].tooltip_text
	_check(tip.contains("program") and not tip.contains("ministry") and tip.contains("improving relations (10)"), "the top bar's tooltip lists the income sources and prices")
	eco.toggle()
	await process_frame
	await process_frame
	_check(eco._program_boxes.has("diplomatic_service") and eco._program_boxes["diplomatic_service"].text.contains("Diplomatic service"), "the Economy window lists the Diplomatic service program")
	_check(eco._program_boxes["diplomatic_service"].tooltip_text.contains("diplomacy points"), "which says what it does (%s)" % eco._program_boxes["diplomatic_service"].tooltip_text)
	eco._program_boxes["diplomatic_service"].toggled.emit(true)
	await process_frame
	_check(gs.nations["FRA"].programs.has("diplomatic_service") and bar._points_gain.text == "+%.1f" % Diplomacy_income("FRA"), "switching it on raises the income shown in the top bar (%s)" % bar._points_gain.text)
	eco.close_window()
