extends Node2D

const NationPicker := preload("res://scripts/ui/nation_picker.gd")
const EconomyPanel := preload("res://scripts/ui/economy_panel.gd")
const MilitaryPanel := preload("res://scripts/ui/military_panel.gd")
const CommandPanel := preload("res://scripts/ui/command_panel.gd")
const BuildQueue := preload("res://scripts/ui/build_queue.gd")
const MapModes := preload("res://scripts/ui/map_modes.gd")
const ArmyLayer := preload("res://scripts/map/army_layer.gd")
const NavalBattleScreen := preload("res://scripts/ui/naval_battle_screen.gd")
const AIOverlay := preload("res://scripts/map/ai_overlay.gd")
const SlotLabels := preload("res://scripts/map/slot_labels.gd")
const CityLayer := preload("res://scripts/map/city_layer.gd")
const Map3DMode := preload("res://scripts/map/map_3d.gd")
## How solid the army and fleet banners are while the Construction map mode is on.
const BUILD_MODE_UNIT_ALPHA := 0.25
const EventFeed := preload("res://scripts/ui/event_feed.gd")
const BattleScreen := preload("res://scripts/ui/battle_screen.gd")
const DiplomacyPanel := preload("res://scripts/ui/diplomacy_panel.gd")
const PeaceScreen := preload("res://scripts/ui/peace_screen.gd")
const JoinPrompt := preload("res://scripts/ui/join_prompt.gd")
const EventPrompt := preload("res://scripts/ui/event_prompt.gd")
const SettingsWindow := preload("res://scripts/ui/settings_window.gd")
const SaveWindow := preload("res://scripts/ui/save_window.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const Tutorial := preload("res://scripts/ui/tutorial.gd")
const FocusPanel := preload("res://scripts/ui/focus_panel.gd")
const NavyPanel := preload("res://scripts/ui/navy_panel.gd")
const ConstructionPanel := preload("res://scripts/ui/construction_panel.gd")
const MapView := preload("res://scripts/map/map_view.gd")
const NationStats := preload("res://scripts/ui/nation_stats.gd")
const RankingsWindow := preload("res://scripts/ui/rankings_window.gd")
const ProvincePanel := preload("res://scripts/ui/province_panel.gd")

@onready var map_view: Sprite2D = $MapView
@onready var camera: Camera2D = $Camera
@onready var ui: CanvasLayer = $UI
var province_panel: PanelContainer


func _ready() -> void:
	# The flat map is drawn only when something on the screen changes (a day passes, the mouse or the camera moves),
	# not sixty times a second while it stands still: the map's shader is what the graphics card spends its time on.
	OS.low_processor_usage_mode = true
	UiSettings.apply_saved(get_window())
	map_view.land_style = UiSettings.land_style
	_theme_interface()
	map_view.province_selected.connect(_on_province_selected)
	map_view.province_ordered.connect(_on_right_click)
	map_view.sea_zone_selected.connect(_on_sea_zone_selected)
	var army_layer := ArmyLayer.new()
	add_child(army_layer)
	var fleet_layer := FleetLayer.new()
	add_child(fleet_layer)
	add_child(AIOverlay.new())
	# In the Construction mode the slot numbers are what matters: the armies and fleets fade back.
	map_view.mode_changed.connect(func(mode: int, _sub: String) -> void:
		var faded := mode == MapView.Mode.CONSTRUCTION
		army_layer.modulate.a = BUILD_MODE_UNIT_ALPHA if faded else 1.0
		fleet_layer.modulate.a = BUILD_MODE_UNIT_ALPHA if faded else 1.0
	)
	var city_layer := CityLayer.new()
	city_layer.map_view = map_view
	city_layer.camera = camera
	add_child(city_layer)
	var slot_labels := SlotLabels.new()
	slot_labels.map_view = map_view
	slot_labels.camera = camera
	add_child(slot_labels)
	# The 3D view of the map, off until V (or the Settings window) switches it on.
	var map_3d := Map3DMode.new()
	map_3d.main = self
	add_child(map_3d)
	map_view.province_hovered.connect(army_layer.set_hover)
	map_view.province_selected.connect(army_layer.set_expanded)
	map_view.battle_clicked.connect(func(province: int) -> void:
		get_tree().call_group("battle_screen", "open_battle", GameState.battle_at(province).get("id", 0))
	)
	map_view.army_clicked.connect(func(id: int, additive: bool) -> void:
		get_tree().call_group("military_panel", "select_army", id, additive)
	)
	map_view.box_selected.connect(func(rect: Rect2, additive: bool) -> void:
		get_tree().call_group("military_panel", "select_in_rect", rect, additive)
		get_tree().call_group("navy_panel", "select_in_rect", rect, additive)
	)
	map_view.fleets_clicked.connect(func(ids: Array, additive: bool) -> void:
		var typed: Array[int] = []
		typed.assign(ids)
		get_tree().call_group("navy_panel", "select_fleets", typed, additive)
	)
	map_view.sea_battle_clicked.connect(func(zone: int) -> void:
		get_tree().call_group("naval_battle_screen", "open_battle", GameState.sea_battles.get(zone, {}).get("id", 0))
	)
	map_view.zone_ordered.connect(func(zone: int) -> void:
		get_tree().call_group("navy_panel", "order_zone", zone)
	)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MapData.map_size.x
	camera.limit_bottom = MapData.map_size.y
	camera.zoom = Vector2(0.4, 0.4)
	_focus_on(GameState.player_tag)

	province_panel = ProvincePanel.new()
	ui.add_child(province_panel)
	# The nation screen: one window, a tab for each part of running the nation.
	var screen := NationScreen.new()
	ui.add_child(screen)
	screen.add_page("Overview", "N", OverviewPage.new())
	screen.add_page("Economy", "E", EconomyPanel.new())
	var construction := ConstructionPanel.new()
	construction.map_view = map_view
	screen.add_page("Build", "B", construction)
	construction.connect_map()
	screen.add_page("Military", "M", MilitaryPanel.new())
	screen.add_page("Navy", "Y", NavyPanel.new())
	screen.add_page("Diplomacy", "F", DiplomacyPanel.new())
	screen.add_page("Focus", "O", FocusPanel.new())
	screen.add_page("Rankings", "R", RankingsWindow.new())
	ui.add_child(CommandPanel.new())
	var nation_stats := NationStats.new()
	nation_stats.closed.connect(_end_peek)
	ui.add_child(nation_stats)
	ui.add_child(SettingsWindow.new())
	ui.add_child(SaveWindow.new())
	GameState.autosave_enabled = true
	ui.add_child(EventFeed.new())
	ui.add_child(BattleScreen.new())
	ui.add_child(NavalBattleScreen.new())
	ui.add_child(PeaceScreen.new())
	ui.add_child(JoinPrompt.new())
	ui.add_child(EventPrompt.new())
	var queue := BuildQueue.new()
	queue.province_clicked.connect(func(id: int) -> void:
		camera.position = MapData.provinces[id].center
		_on_province_selected(id)
	)
	ui.add_child(queue)
	var modes := MapModes.new()
	modes.map_view = map_view
	ui.add_child(modes)

	var tutorial := Tutorial.new()
	tutorial.map_view = map_view
	tutorial.camera = camera
	ui.add_child(tutorial)

	# First in the tree, so it sees an Esc after every panel that uses one.
	var pause := PauseMenu.new()
	add_child(pause)
	GameState.menu_requested.connect(pause.to_main_menu)
	move_child(pause, 0)

	# A loaded game goes on as the nation that was saved; a new one asks which to play.
	if Scenarios.resume:
		Scenarios.resume = false
		_focus_on(GameState.player_tag)
		return
	var picker := NationPicker.new()
	picker.map_view = map_view
	picker.nation_chosen.connect(func(tag: String) -> void:
		picker.queue_free()
		GameState.set_player(tag)
		_focus_on(tag)
		tutorial.after_nation_chosen()
	)
	ui.add_child(picker)


## A control under a CanvasLayer does not pick up the theme of the window, so the layer's windows,
## bars and panels are given it one by one (those that bring a theme of their own keep it): the
## same serif face, colours and frames everywhere.
func _theme_interface() -> void:
	var shared: Theme = get_window().theme
	for child in ui.get_children():
		_give_theme(child, shared)
	ui.child_entered_tree.connect(func(child: Node) -> void: _give_theme(child, shared))


static func _give_theme(node: Node, shared: Theme) -> void:
	if node is Control and node.theme == null:
		node.theme = shared


## The nation a right click has put on show, and the map mode to go back to when it is put
## away ("" and -1 when nothing is on show).
var _peek_tag := ""
var _peek_mode := -1
var _peek_submode := ""


## A right click on a province, as in the Paradox games: with armies selected it is an order.
## Otherwise it picks the nation that owns the land: your own opens the Nation screen; another one opens the
## country panel on the left on it and the map goes to the Diplomacy mode seen from that nation. Right-
## clicking the same nation again, or closing the panel, puts the map back as it was. Holding
## Shift picks the nation for the panel only, leaving the map mode alone.
func _on_right_click(id: int) -> void:
	var tag: String = GameState.province_owner[id]
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var navy := get_tree().get_first_node_in_group("navy_panel")
	if navy != null and navy.has_selection() and not shift and navy.order_port(id):
		return
	var panel := get_tree().get_first_node_in_group("military_panel")
	if panel != null and panel.has_selection() and not shift:
		get_tree().call_group("military_panel", "order_move", id)
		return
	if tag == GameState.player_tag and not shift:
		# Your own nation is the Nation screen's business; the country panel is for looking at the others.
		get_tree().call_group("nation_screen", "open_page", "Overview")
		return
	var stats := get_tree().get_first_node_in_group("nation_stats")
	if shift:
		_peek_tag = ""
		_peek_mode = -1
		get_tree().call_group("nation_stats", "show_nation", tag)
		return
	if _peek_tag == tag and stats != null and stats.visible:
		_end_peek()
		stats.close_window()
		return
	if _peek_tag == "":
		# The map mode to come back to; none if it is already the Diplomacy mode.
		_peek_mode = -1 if map_view.mode == MapView.Mode.DIPLOMACY else map_view.mode
		_peek_submode = map_view.submode
		if map_view.mode != MapView.Mode.DIPLOMACY:
			map_view.set_mode(MapView.Mode.DIPLOMACY)
	_peek_tag = tag
	map_view.set_viewpoint(tag)
	get_tree().call_group("diplomacy_panel", "set_province", id)
	get_tree().call_group("nation_stats", "show_nation", tag)


## Puts the map back after a nation was put on show: the point of view is the player's again
## and the map mode returns, unless the player has picked another one since.
func _end_peek() -> void:
	if _peek_tag == "":
		return
	_peek_tag = ""
	map_view.set_viewpoint("")
	if _peek_mode >= 0 and map_view.mode == MapView.Mode.DIPLOMACY:
		map_view.set_mode(_peek_mode, _peek_submode)
	_peek_mode = -1


## Centers the camera on a nation's population-weighted middle.
func _focus_on(tag: String) -> void:
	var nation: Nation = GameState.nations.get(tag)
	if nation == null or nation.provinces.is_empty():
		camera.position = Vector2(MapData.map_size) * 0.5
		return
	var sum := Vector2.ZERO
	var weight := 0.0
	for id in nation.provinces:
		var w := float(GameState.province_population[id])
		sum += MapData.provinces[id].center * w
		weight += w
	camera.position = sum / maxf(weight, 1.0)
	camera.zoom = Vector2(0.6, 0.6)


func _on_sea_zone_selected(zone: int) -> void:
	if zone <= 0:
		return
	get_tree().call_group("navy_panel", "clear_selection_quiet")
	province_panel.show_zone(zone)


func _on_province_selected(id: int) -> void:
	get_tree().call_group("navy_panel", "clear_selection_quiet")
	get_tree().call_group("navy_panel", "set_province", id)
	get_tree().call_group("economy_panel", "set_province", id)
	get_tree().call_group("military_panel", "set_province", id)
	get_tree().call_group("diplomacy_panel", "set_province", id)
	province_panel.show_province(id)
