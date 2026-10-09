extends Node2D

const NationPicker := preload("res://scripts/ui/nation_picker.gd")
const EconomyPanel := preload("res://scripts/ui/economy_panel.gd")
const MilitaryPanel := preload("res://scripts/ui/military_panel.gd")
const BuildQueue := preload("res://scripts/ui/build_queue.gd")
const MapModes := preload("res://scripts/ui/map_modes.gd")
const ArmyLayer := preload("res://scripts/map/army_layer.gd")
const EventFeed := preload("res://scripts/ui/event_feed.gd")
const BattleScreen := preload("res://scripts/ui/battle_screen.gd")
const DiplomacyPanel := preload("res://scripts/ui/diplomacy_panel.gd")
const PeaceScreen := preload("res://scripts/ui/peace_screen.gd")
const JoinPrompt := preload("res://scripts/ui/join_prompt.gd")
const SettingsWindow := preload("res://scripts/ui/settings_window.gd")
const MapView := preload("res://scripts/map/map_view.gd")
const NationStats := preload("res://scripts/ui/nation_stats.gd")
const RankingsWindow := preload("res://scripts/ui/rankings_window.gd")

@onready var map_view: Sprite2D = $MapView
@onready var camera: Camera2D = $Camera
@onready var ui: CanvasLayer = $UI
@onready var info_label: Label = $UI/InfoLabel


func _ready() -> void:
	UiSettings.apply_saved(get_window())
	map_view.province_selected.connect(_on_province_selected)
	map_view.province_ordered.connect(_on_right_click)
	var army_layer := ArmyLayer.new()
	add_child(army_layer)
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
	)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MapData.map_size.x
	camera.limit_bottom = MapData.map_size.y
	camera.zoom = Vector2(0.4, 0.4)
	_focus_on(GameState.player_tag)

	ui.add_child(EconomyPanel.new())
	ui.add_child(MilitaryPanel.new())
	ui.add_child(DiplomacyPanel.new())
	ui.add_child(NationStats.new())
	ui.add_child(RankingsWindow.new())
	ui.add_child(SettingsWindow.new())
	ui.add_child(EventFeed.new())
	ui.add_child(BattleScreen.new())
	ui.add_child(PeaceScreen.new())
	ui.add_child(JoinPrompt.new())
	var queue := BuildQueue.new()
	queue.province_clicked.connect(func(id: int) -> void:
		camera.position = MapData.provinces[id].center
		_on_province_selected(id)
	)
	ui.add_child(queue)
	var modes := MapModes.new()
	modes.map_view = map_view
	ui.add_child(modes)

	var picker := NationPicker.new()
	picker.nation_chosen.connect(func(tag: String) -> void:
		GameState.set_player(tag)
		_focus_on(tag)
		picker.queue_free()
	)
	ui.add_child(picker)


## A right click on a province, as in the Paradox games: with armies selected it is an order.
## Otherwise it picks the nation that owns the land: the country panel on the left changes to
## it (your own nation too), and in the Diplomacy map mode the map's point of view moves to it
## as well (your own nation returns it to yours). Holding Shift picks the nation for the panel
## only, whatever the mode and whatever is selected.
func _on_right_click(id: int) -> void:
	var tag: String = GameState.province_owner[id]
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var panel := get_tree().get_first_node_in_group("military_panel")
	if panel != null and panel.has_selection() and not shift:
		get_tree().call_group("military_panel", "order_move", id)
		return
	if map_view.mode == MapView.Mode.DIPLOMACY and not shift:
		map_view.set_viewpoint(tag)
		get_tree().call_group("diplomacy_panel", "set_province", id)
	get_tree().call_group("nation_stats", "show_nation", tag)


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


func _on_province_selected(id: int) -> void:
	get_tree().call_group("economy_panel", "set_province", id)
	get_tree().call_group("military_panel", "set_province", id)
	get_tree().call_group("diplomacy_panel", "set_province", id)
	var p := MapData.get_province(id)
	if p.is_empty():
		info_label.text = "Click a province"
		return
	var owner_tag: String = GameState.province_owner[id]
	var population: int = GameState.province_population[id]
	var lines: PackedStringArray = [
		"%s%s" % [p.name, "  (coast)" if p.coastal else ""],
		"%s, %s people, ~%s km²" % [GameState.nations[owner_tag].display_name, Fmt.thousands(population), Fmt.thousands(int(p.area * MapData.KM2_PER_PX))],
		"Output £%.1fM a month, feeds %s, recruits %s" % [
			Fmt.monthly(GameState.province_gdp[id]), Fmt.people(GameState.province_food[id]), Fmt.people(GameState.province_pool[id])],
	]

	lines[0] += "  [%s]" % Military.terrain_of(id).name.to_lower()
	if GameState.province_controller[id] != owner_tag:
		lines.append("Occupied by %s" % GameState.nations[GameState.province_controller[id]].display_name)
	var here := Military.armies_at(GameState, id)
	if not here.is_empty():
		var parts: PackedStringArray = []
		for a in here:
			parts.append("%s %s (%s)" % [a.tag, a.display_name, Fmt.people(a.men())])
		lines.append("Armies: " + "; ".join(parts))

	var made := Economy.province_output(population, p.area * MapData.KM2_PER_PX, GameState.nations[owner_tag],
			GameState.province_buildings[id], GameState.province_deposit[id])
	var deposits: PackedStringArray = []
	for r in Economy.resource_ids():
		if GameState.province_deposit[id].get(r, 0.0) >= Economy.cfg.min_deposit:
			deposits.append("%s %s/mo" % [Economy.cfg.resources[r].name.to_lower(), Fmt.kt(Fmt.monthly(made[r]))])
	if not deposits.is_empty():
		lines.append("Mines: " + ", ".join(deposits))

	var built: PackedStringArray = []
	for type in Economy.building_ids():
		if GameState.province_buildings[id].has(type):
			built.append("%s %d" % [Economy.cfg.buildings[type].name, GameState.province_buildings[id][type]])
	if not built.is_empty():
		lines.append("Built: " + ", ".join(built))
	info_label.text = "\n".join(lines)
