extends Sprite2D
## Draws the province bitmap through shaders/map.gdshader and handles picking. A map mode
## decides what color each province is painted; some modes have submodes (which resource,
## which building). Colors go into a lookup texture, so changing a mode or the data behind it
## only rewrites one pixel per province.

signal province_hovered(id: int)
signal province_selected(id: int)
## Right click: orders (move an army here).
signal province_ordered(id: int)
## A rectangle was dragged on the map (in map coordinates); `additive` if Shift was held.
signal box_selected(rect: Rect2, additive: bool)
## A fanned-out army banner was clicked (see ArmyLayer); `additive` if Shift was held.
signal army_clicked(army_id: int, additive: bool)
## The icon of a battle in progress was clicked (its province).
signal battle_clicked(province: int)
signal mode_changed(mode: Mode, submode: String)
## In the Diplomacy mode, whose point of view the map shows changed (see set_viewpoint).
signal viewpoint_changed(tag: String)

enum Mode { POLITICAL, RESOURCES, INCOME, POPULATION, BUILDINGS, PROVINCES, TERRAIN, MILITARY, DIPLOMACY }
const MODE_NAMES := {
	Mode.POLITICAL: "Political",
	Mode.RESOURCES: "Resources",
	Mode.INCOME: "Income",
	Mode.POPULATION: "Population",
	Mode.BUILDINGS: "Buildings",
	Mode.PROVINCES: "Provinces",
	Mode.TERRAIN: "Terrain",
	Mode.MILITARY: "Military",
	Mode.DIPLOMACY: "Diplomacy",
}
## Modes whose colors depend on data that changes as the game runs.
const DYNAMIC_MODES := [Mode.INCOME, Mode.BUILDINGS, Mode.MILITARY, Mode.DIPLOMACY]
## Diplomacy mode: opinion of the player runs from HOSTILE through NEUTRAL to FRIENDLY.
const HOSTILE_COLOR := Color(0.82, 0.25, 0.22)
const NEUTRAL_COLOR := Color(0.8, 0.8, 0.76)
const FRIENDLY_COLOR := Color(0.25, 0.65, 0.35)
const SELF_COLOR := Color(0.78, 0.86, 1.0)
const ALLY_COLOR := Color(0.12, 0.62, 0.78)
const WAR_COLOR := Color(0.5, 0.06, 0.08)
const GUARANTEE_HATCH := Color(1.0, 1.0, 1.0)
## Outline colours of the blocs, in the order the scenario lists them.
const BLOC_COLORS := [Color(0.2, 0.4, 0.95), Color(0.95, 0.75, 0.1), Color(0.8, 0.3, 0.9), Color(0.1, 0.8, 0.5)]
## Base color of each shaded mode; low values fade toward NO_DATA_COLOR.
const MODE_COLORS := {
	Mode.INCOME: Color(0.18, 0.62, 0.3),
	Mode.POPULATION: Color(0.66, 0.3, 0.55),
	Mode.BUILDINGS: Color(0.25, 0.45, 0.82),
}
const NO_DATA_COLOR := Color(0.8, 0.8, 0.76)
const ALL_BUILDINGS := "all"
const LOOKUP_WIDTH := 256

var mode: Mode = Mode.POLITICAL
## Which resource or building a mode shows; "" when the mode has no submodes.
var submode := ""
var selected_id := 0
var hover_id := 0

## Drag selection: where the left button went down (screen and map), and whether it has
## moved far enough to be a box rather than a click.
const DRAG_PIXELS := 8.0
var _pressing := false
var _boxing := false
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO

var _lookup_image: Image
var _lookup_texture: ImageTexture
var _owner_image: Image
var _owner_texture: ImageTexture
var _marks_image: Image
var _marks_texture: ImageTexture
var _blocs_image: Image
var _blocs_texture: ImageTexture
var _repaint_queued := false
## Diplomacy mode: the nation whose relations the map shows. "" means the player's own.
var viewpoint := ""
## The mode and submode to go back to after push_mode.
var _pushed_mode := -1
var _pushed_submode := ""
var _material: ShaderMaterial
## Largest value of the current mode, for the legend and the color scale.
var _max_value := 0.0


func _ready() -> void:
	add_to_group("map_view")
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ImageTexture.create_from_image(MapData.provinces_image)

	var max_id := MapData.provinces.size() - 1
	_lookup_image = Image.create(LOOKUP_WIDTH, ceili((max_id + 1) / float(LOOKUP_WIDTH)), false, Image.FORMAT_RGBA8)
	_owner_image = _lookup_image.duplicate()
	_lookup_texture = ImageTexture.create_from_image(_lookup_image)
	_owner_texture = ImageTexture.create_from_image(_owner_image)
	_marks_image = _lookup_image.duplicate()
	_blocs_image = _lookup_image.duplicate()
	_marks_texture = ImageTexture.create_from_image(_marks_image)
	_blocs_texture = ImageTexture.create_from_image(_blocs_image)

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/map.gdshader")
	_material.set_shader_parameter("provinces", texture)
	_material.set_shader_parameter("lookup", _lookup_texture)
	_material.set_shader_parameter("owners", _owner_texture)
	_material.set_shader_parameter("marks", _marks_texture)
	_material.set_shader_parameter("blocs", _blocs_texture)
	_material.set_shader_parameter("lookup_width", LOOKUP_WIDTH)
	_material.set_shader_parameter("max_id", max_id)
	_material.set_shader_parameter("map_size", Vector2(MapData.map_size))
	material = _material

	GameState.province_owner_changed.connect(func(_id: int, _old: String, _new: String) -> void: repaint())
	GameState.province_controller_changed.connect(func(_id: int, _old: String, _new: String) -> void:
		if mode == Mode.MILITARY or mode == Mode.POLITICAL:
			repaint()
	)
	GameState.economy_updated.connect(func() -> void:
		if mode in DYNAMIC_MODES and mode != Mode.DIPLOMACY:
			repaint()
	)
	# Opinions change all the time; repaint the diplomacy mode at most once a frame.
	GameState.relations_changed.connect(_queue_repaint.unbind(2))
	GameState.treaty_changed.connect(_queue_repaint.unbind(2))
	GameState.war_changed.connect(_queue_repaint.unbind(3))
	GameState.player_changed.connect(_queue_repaint.unbind(1))
	GameState.player_changed.connect(func(_t: String) -> void: set_viewpoint(""))
	set_mode(Mode.POLITICAL)


## The submodes of a mode as [id, label] pairs (empty if it has none).
func submodes(for_mode: Mode = mode) -> Array:
	var list := []
	match for_mode:
		Mode.RESOURCES:
			for r in Economy.resource_ids():
				list.append([r, Economy.cfg.resources[r].name])
		Mode.BUILDINGS:
			list.append([ALL_BUILDINGS, "All except mines"])
			for type in Economy.building_ids():
				list.append([type, Economy.cfg.buildings[type].name])
	return list


func set_mode(new_mode: Mode, new_submode := "") -> void:
	if new_mode != Mode.DIPLOMACY and viewpoint != "":
		viewpoint = ""
		viewpoint_changed.emit(GameState.player_tag)
	mode = new_mode
	var options := submodes(new_mode)
	submode = ""
	if not options.is_empty():
		submode = new_submode
		if options.filter(func(o: Array) -> bool: return o[0] == submode).is_empty():
			submode = options[0][0]
	_material.set_shader_parameter("mode", 1 if mode == Mode.PROVINCES else 0)
	_material.set_shader_parameter("occupation_stripes", mode == Mode.POLITICAL)
	_material.set_shader_parameter("diplomacy", mode == Mode.DIPLOMACY)
	repaint()
	mode_changed.emit(mode, submode)


## Steps to the next submode of the current mode, if it has any.
func cycle_submode() -> void:
	var options := submodes()
	if options.size() < 2:
		return
	for i in options.size():
		if options[i][0] == submode:
			set_mode(mode, options[(i + 1) % options.size()][0])
			return


## Shows a mode for as long as a window that wants it is open, remembering the one to return
## to (see pop_mode). Does nothing if that mode is already showing.
func push_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		return
	_pushed_mode = mode
	_pushed_submode = submode
	set_mode(new_mode)


## Goes back to the mode before push_mode, unless the player has chosen another one since.
func pop_mode(pushed: Mode) -> void:
	if _pushed_mode >= 0 and mode == pushed:
		var back := _pushed_mode
		_pushed_mode = -1
		set_mode(back, _pushed_submode)
	else:
		_pushed_mode = -1


## The nation whose diplomatic point of view the Diplomacy mode shows: the one picked with
## a right click, or the player's own.
func diplomacy_viewpoint() -> String:
	if viewpoint != "" and GameState.nations.has(viewpoint):
		return viewpoint
	return GameState.player_tag


## Shows the Diplomacy mode from another nation's point of view: who it is allied with, at war
## with, and how it is regarded. The player's own nation (or "") goes back to the player's view.
func set_viewpoint(tag: String) -> void:
	var wanted := "" if tag == GameState.player_tag or not GameState.nations.has(tag) else tag
	if wanted == viewpoint:
		return
	viewpoint = wanted
	if mode == Mode.DIPLOMACY:
		repaint()
	viewpoint_changed.emit(diplomacy_viewpoint())


func _queue_repaint() -> void:
	if mode != Mode.DIPLOMACY or _repaint_queued:
		return
	_repaint_queued = true
	_deferred_repaint.call_deferred()


func _deferred_repaint() -> void:
	_repaint_queued = false
	if mode == Mode.DIPLOMACY:
		repaint()


## Colour of a nation in diplomacy mode, seen from the viewpoint nation (the player's unless
## another was picked): its own, its allies, its enemies at war, and everyone else on a
## hostile-to-friendly scale of how it regards them.
func diplomacy_color(tag: String) -> Color:
	var me := diplomacy_viewpoint()
	if tag == me:
		return SELF_COLOR
	if GameState.at_war(me, tag):
		return WAR_COLOR
	var ally := Diplomacy.find_treaty(GameState, "alliance", me, tag)
	if ally != null and not ally.terms.get("entente", false):
		return ALLY_COLOR
	var r := Diplomacy.relation(GameState, me, tag)
	if r >= 0.0:
		return NEUTRAL_COLOR.lerp(FRIENDLY_COLOR, r / 100.0)
	return NEUTRAL_COLOR.lerp(HOSTILE_COLOR, -r / 100.0)


## Outline colour of a nation's bloc, or transparent if it is in none.
func bloc_color(tag: String) -> Color:
	var name := Diplomacy.bloc_of(GameState, tag)
	if name == "":
		return Color(0, 0, 0, 0)
	var names: Array = GameState.scenario.get("blocs", {}).keys()
	return BLOC_COLORS[names.find(name) % BLOC_COLORS.size()]


## Re-reads the data behind the current mode and repaints every province.
func repaint() -> void:
	var count := MapData.provinces.size()
	var values := PackedFloat32Array()
	values.resize(count)
	_max_value = 0.0
	if MODE_COLORS.has(mode) or mode == Mode.RESOURCES:
		for id in range(1, count):
			values[id] = _value(id)
			_max_value = maxf(_max_value, values[id])
	for id in range(1, count):
		@warning_ignore("integer_division")
		var px := Vector2i(id % LOOKUP_WIDTH, id / LOOKUP_WIDTH)
		_owner_image.set_pixelv(px, GameState.owner_color(id))
		_lookup_image.set_pixelv(px, _paint_color(id, values[id]))
	_lookup_texture.update(_lookup_image)
	_owner_texture.update(_owner_image)
	if mode == Mode.DIPLOMACY:
		_paint_diplomacy_marks()


## Fills the hatch (guaranteed nations) and bloc outline textures for diplomacy mode.
func _paint_diplomacy_marks() -> void:
	var hatched := {}
	var blocs := {}
	for tag: String in GameState.nations:
		hatched[tag] = not Diplomacy.guarantors_of(GameState, tag).is_empty()
		blocs[tag] = bloc_color(tag)
	for id in range(1, MapData.provinces.size()):
		@warning_ignore("integer_division")
		var px := Vector2i(id % LOOKUP_WIDTH, id / LOOKUP_WIDTH)
		var tag: String = GameState.province_owner[id]
		_marks_image.set_pixelv(px, GUARANTEE_HATCH if hatched[tag] else Color(0, 0, 0, 0))
		_blocs_image.set_pixelv(px, blocs[tag])
	_marks_texture.update(_marks_image)
	_blocs_texture.update(_blocs_image)


## The number a province is shaded by in the current mode.
func _value(id: int) -> float:
	match mode:
		Mode.RESOURCES:
			var amount: float = GameState.province_deposit[id].get(submode, 0.0)
			return amount if amount >= Economy.cfg.min_deposit else 0.0
		Mode.INCOME:
			# Tax the province yields each month.
			return Fmt.monthly(GameState.province_gdp[id]) * GameState.nations[GameState.province_owner[id]].tax_rate
		Mode.POPULATION:
			return float(GameState.province_population[id])
		Mode.BUILDINGS:
			var levels := 0
			for type in GameState.province_buildings[id]:
				if submode == ALL_BUILDINGS:
					if not str(Economy.cfg.buildings[type].get("requires", "")).begins_with("deposit:"):
						levels += GameState.province_buildings[id][type]
				elif type == submode:
					levels += GameState.province_buildings[id][type]
			return float(levels)
	return 0.0


## Colour of a province in the current mode, given its value.
func _paint_color(id: int, value: float) -> Color:
	if mode == Mode.TERRAIN:
		return Color(Military.terrain_of(id).color)
	if mode == Mode.DIPLOMACY:
		return diplomacy_color(GameState.province_owner[id])
	if mode == Mode.MILITARY or mode == Mode.POLITICAL:
		# Who holds the ground. Political stripes occupied provinces with the owner's colour
		# (in the shader); Military paints them solid in the occupier's colour.
		return GameState.nations[GameState.province_controller[id]].color
	if mode != Mode.RESOURCES and not MODE_COLORS.has(mode):
		return GameState.owner_color(id)
	if value <= 0.0:
		return NO_DATA_COLOR
	return NO_DATA_COLOR.lerp(_mode_color(), 0.25 + 0.75 * _scale(value))


## 0..1 position of a value on the mode's color scale: deposits span orders of magnitude, so
## they use a log scale; everything else uses a square root so small values stay visible.
func _scale(value: float) -> float:
	if _max_value <= 0.0:
		return 0.0
	if mode == Mode.RESOURCES:
		var floor_value: float = Economy.cfg.min_deposit
		return clampf(log(maxf(value, floor_value) / floor_value) / maxf(log(_max_value / floor_value), 0.001), 0.0, 1.0)
	return clampf(sqrt(value / _max_value), 0.0, 1.0)


func _mode_color() -> Color:
	if mode == Mode.RESOURCES:
		return Color(Economy.cfg.resources[submode].color)
	return MODE_COLORS[mode]


## What the legend should show for the current mode: a title, the ends of the color scale,
## and its color. Empty for modes that are not shaded.
func legend() -> Dictionary:
	if mode == Mode.DIPLOMACY:
		return {"title": "Opinion of %s" % GameState.nations[diplomacy_viewpoint()].display_name if GameState.nations.has(diplomacy_viewpoint()) else "Opinion",
				"low": "hostile", "high": "friendly", "from": HOSTILE_COLOR, "to": FRIENDLY_COLOR}
	if mode != Mode.RESOURCES and not MODE_COLORS.has(mode):
		return {}
	var title := ""
	var high := ""
	match mode:
		Mode.RESOURCES:
			title = "%s per month" % Economy.cfg.resources[submode].name
			high = Fmt.kt(Fmt.monthly(_max_value))
		Mode.INCOME:
			title = "Tax income per month"
			high = "£%.1fM" % _max_value
		Mode.POPULATION:
			title = "Population"
			high = Fmt.people(_max_value)
		Mode.BUILDINGS:
			title = "Building levels"
			high = "%d" % roundi(_max_value) if _max_value > 0.0 else "none built yet"
	return {"title": title, "low": "none", "high": high,
			"from": NO_DATA_COLOR.lerp(_mode_color(), 0.25), "to": _mode_color()}


func select(id: int) -> void:
	selected_id = id
	_material.set_shader_parameter("selected_id", id)
	province_selected.emit(id)


func _box_rect() -> Rect2:
	return Rect2(_press_world, get_global_mouse_position() - _press_world).abs()


## The left button came up: a drag selects armies in the box, a click selects the province.
func _finish_press(_screen_pos: Vector2) -> void:
	var was_box := _boxing
	_pressing = false
	_boxing = false
	if was_box:
		get_tree().call_group("army_layer", "set_box", Rect2())
		box_selected.emit(_box_rect(), Input.is_key_pressed(KEY_SHIFT))
	else:
		var layer := get_tree().get_first_node_in_group("army_layer")
		var battle: int = layer.pick_battle_at(get_global_mouse_position()) if layer != null else 0
		var hit: int = layer.pick_at(get_global_mouse_position()) if layer != null else 0
		if battle > 0:
			battle_clicked.emit(battle)
		elif hit > 0:
			army_clicked.emit(hit, Input.is_key_pressed(KEY_SHIFT))
		else:
			select(maxi(_province_under_mouse(), 0))


func _province_under_mouse() -> int:
	var px := Vector2i(to_local(get_global_mouse_position()).floor())
	return MapData.province_at_pixel(px)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := maxi(_province_under_mouse(), 0)
		if id != hover_id:
			hover_id = id
			_material.set_shader_parameter("hover_id", hover_id)
			province_hovered.emit(hover_id)
		if _pressing:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_finish_press(event.position)  # the release went to a menu
			else:
				if not _boxing and event.position.distance_to(_press_screen) > DRAG_PIXELS:
					_boxing = true
				if _boxing:
					get_tree().call_group("army_layer", "set_box", _box_rect())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_boxing = false
			_press_screen = event.position
			_press_world = get_global_mouse_position()
		elif _pressing:
			_finish_press(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var target := _province_under_mouse()
		if target > 0:
			province_ordered.emit(target)
