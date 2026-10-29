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
## A sea zone was clicked (0 when a province or nothing was).
signal sea_zone_selected(zone: int)
## A banner of fleets was clicked (their ids); `additive` if Shift was held.
signal fleets_clicked(ids: Array, additive: bool)
## The icon of a sea battle was clicked (its zone).
signal sea_battle_clicked(zone: int)
## Right click on water: orders (send the selected fleets there).
signal zone_ordered(zone: int)
signal mode_changed(mode: Mode, submode: String)
## In the Diplomacy mode, whose point of view the map shows changed (see set_viewpoint).
signal viewpoint_changed(tag: String)

enum Mode { POLITICAL, RESOURCES, INCOME, POPULATION, BUILDINGS, PROVINCES, TERRAIN, MILITARY, DIPLOMACY, SEA_CONTROL, BLOCKADE, CONSTRUCTION }
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
	Mode.SEA_CONTROL: "Sea control",
	Mode.BLOCKADE: "Blockade",
	Mode.CONSTRUCTION: "Construction",
}
## Modes whose colors depend on data that changes as the game runs.
const DYNAMIC_MODES := [Mode.INCOME, Mode.BUILDINGS, Mode.MILITARY, Mode.DIPLOMACY, Mode.SEA_CONTROL, Mode.BLOCKADE, Mode.CONSTRUCTION]
## The modes that tint the sea zones.
const NAVAL_MODES := [Mode.SEA_CONTROL, Mode.BLOCKADE]
## The map modes that paint nations, and so show the land texture under their colours.
const LAND_TEXTURE_MODES := [Mode.POLITICAL, Mode.DIPLOMACY, Mode.MILITARY]
## How much of the land texture shows (0 to 1) when zoomed far out and when zoomed right in.
const LAND_BLEND_FAR := 0.3
const LAND_BLEND_NEAR := 0.9
## The land textures: the blend of the ground's own colour at the far and near ends of the zoom.
const LAND_STYLES := {
	"satellite": {"path": "res://data/map/land_satellite.jpg", "far": 0.2, "near": 0.9},
	"painted": {"path": "res://data/map/land_painted.jpg", "far": 0.1, "near": 0.7},
}
const BLOCKADE_COLOR := Color(0.78, 0.12, 0.1)
const CONTESTED_COLOR := Color(0.6, 0.1, 0.1)
const ZONE_TEXTURE_WIDTH := 64

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
## Construction mode (the building picked is the submode): what the player's provinces show.
const CONSTRUCT_OTHER := Color(0.16, 0.18, 0.22)
const CONSTRUCT_BLOCKED := Color(0.5, 0.5, 0.53)
const CONSTRUCT_BUILD := Color(0.25, 0.74, 0.36)
const CONSTRUCT_BOTH := Color(0.2, 0.7, 0.7)
const CONSTRUCT_HAVE := Color(0.25, 0.45, 0.82)
const ALL_BUILDINGS := "all"
## Military mode (the variant is the submode): who holds the ground, where the front is, how many
## men stand in each province.
const MIL_CONTROL := "control"
const MIL_FRONT := "front"
const MIL_STRENGTH := "strength"
const MIL_SUPPLY := "supply"
const SUPPLY_HOME := Color(0.36, 0.7, 0.36)
const SUPPLY_NEAR := Color(0.78, 0.8, 0.3)
const SUPPLY_FAR := Color(0.9, 0.58, 0.2)
const SUPPLY_NONE := Color(0.8, 0.2, 0.18)
const FRONT_HOT := Color(0.86, 0.2, 0.16)
const STRENGTH_COLOR := Color(0.85, 0.35, 0.2)
const LOOKUP_WIDTH := 256

var mode: Mode = Mode.POLITICAL
## Which resource or building a mode shows; "" when the mode has no submodes.
var submode := ""
var selected_id := 0
var hover_id := 0
var selected_zone := 0
var hover_zone := 0
## Whether the borders of every sea zone are drawn (Z toggles it).
var show_zones := false

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
## Provinces a plan of attack means to take, painted with stripes in the army's colour (set_plan_zone).
var _plans_image: Image
var _plans_texture: ImageTexture
var _plan_signature := []
var _marks_texture: ImageTexture
var _blocs_image: Image
var _blocs_texture: ImageTexture
var _zone_image: Image
var _zone_texture: ImageTexture
var _repaint_queued := false
## Diplomacy mode: the nation whose relations the map shows. "" means the player's own.
var viewpoint := ""
## The mode and submode to go back to after push_mode.
var _pushed_mode := -1
var _pushed_submode := ""
var _material: ShaderMaterial
## Which land texture shows under the nations' colours: "satellite", "painted" or "off" (see the
## Settings window).
var land_style := "satellite":
	set(value):
		land_style = value if value == "off" or LAND_STYLES.has(value) else "satellite"
		_apply_land_style()
## The 3D map asks for the land texture as if the camera were at least this close (it shows the
## ground from a slant, where the political colours alone look flat).
var land_zoom_floor := 0.0:
	set(value):
		land_zoom_floor = value
		_land_zoom = -1.0
var _land_zoom := -1.0
var _land_textures := {}
## Military mode's figures, worked out once per repaint: men in each province.
var _men_at := {}
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
	# Zoomed out, a screen pixel covers several map pixels, and the full-size picture of the provinces (120 MB)
	# is read all over, which is what slows the map on a modest graphics card: half and quarter size pictures
	# of it (the nearest pixel of each block) serve for those zooms, and fit in the card's cache.
	for step in [2, 4]:
		var small := MapData.provinces_image.duplicate() as Image
		small.resize(MapData.map_size.x / step, MapData.map_size.y / step, Image.INTERPOLATE_NEAREST)
		_material.set_shader_parameter("provinces_half" if step == 2 else "provinces_quarter", ImageTexture.create_from_image(small))
	_material.set_shader_parameter("lookup", _lookup_texture)
	_material.set_shader_parameter("owners", _owner_texture)
	_material.set_shader_parameter("marks", _marks_texture)
	_plans_image = _lookup_image.duplicate()
	_plans_texture = ImageTexture.create_from_image(_plans_image)
	_material.set_shader_parameter("plans", _plans_texture)
	_material.set_shader_parameter("blocs", _blocs_texture)
	_material.set_shader_parameter("sea_zones", ImageTexture.create_from_image(MapData.sea_zones_image))
	_zone_image = Image.create(ZONE_TEXTURE_WIDTH, 1, false, Image.FORMAT_RGBA8)
	_zone_texture = ImageTexture.create_from_image(_zone_image)
	_material.set_shader_parameter("zone_colors", _zone_texture)
	_material.set_shader_parameter("lookup_width", LOOKUP_WIDTH)
	_material.set_shader_parameter("max_id", max_id)
	_material.set_shader_parameter("map_size", Vector2(MapData.map_size))
	land_style = UiSettings.land_style
	material = _material

	GameState.scenario_loaded.connect(repaint)
	GameState.province_owner_changed.connect(func(_id: int, _old: String, _new: String) -> void: repaint())
	GameState.province_controller_changed.connect(func(_id: int, _old: String, _new: String) -> void:
		if mode == Mode.MILITARY or mode == Mode.POLITICAL:
			repaint()
	)
	GameState.armies_changed.connect(_queue_military_repaint)
	GameState.economy_updated.connect(func() -> void:
		if mode in DYNAMIC_MODES and mode != Mode.DIPLOMACY:
			repaint()
	)
	# Ships come and go every day; repaint the sea modes at most once a frame.
	GameState.fleets_changed.connect(_queue_naval_repaint)
	GameState.blockade_changed.connect(_queue_naval_repaint.unbind(2))
	# Opinions change all the time; repaint the diplomacy mode at most once a frame.
	GameState.relations_changed.connect(_queue_repaint.unbind(2))
	GameState.treaty_changed.connect(_queue_repaint.unbind(2))
	GameState.war_changed.connect(_queue_repaint.unbind(3))
	GameState.player_changed.connect(_queue_repaint.unbind(1))
	GameState.player_changed.connect(func(_t: String) -> void: set_viewpoint(""))
	set_mode(Mode.POLITICAL)


## The submodes of a mode as [id, label] pairs (empty if it has none).
## The land texture shows more the closer the camera is.
static func land_blend_for(zoom: float) -> float:
	var t := clampf((zoom - 0.2) / 0.8, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(LAND_BLEND_FAR, LAND_BLEND_NEAR, t)


## The share of the ground's own colour in the blend: little from afar, much close up.
static func land_natural_for(zoom: float, style := "satellite") -> float:
	var t := clampf((zoom - 0.25) / 0.85, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var ends: Dictionary = LAND_STYLES.get(style, LAND_STYLES.satellite)
	return lerpf(ends.far, ends.near, t)


## Loads the chosen texture into the shader and switches the blend on or off.
func _apply_land_style() -> void:
	if _material == null:
		return
	if land_style != "off":
		var texture: Texture2D = _land_textures.get(land_style)
		if texture == null:
			texture = load(LAND_STYLES[land_style].path)
			_land_textures[land_style] = texture
		_material.set_shader_parameter("land_texture", texture)
	_material.set_shader_parameter("land_on", land_style != "off" and mode in LAND_TEXTURE_MODES)
	_land_zoom = -1.0


func _process(_delta: float) -> void:
	if _tip_layer != null and _tip.visible and (_over_interface() or (mode != Mode.DIPLOMACY and not _orders_selected())):
		_tip.visible = false
	var camera := get_viewport().get_camera_2d()
	if camera != null and _material != null and not is_equal_approx(camera.zoom.x, _land_zoom) or (_land_zoom < 0.0 and _material != null and camera != null):
		_land_zoom = camera.zoom.x
		var zoom := maxf(_land_zoom, land_zoom_floor)
		_material.set_shader_parameter("land_blend", land_blend_for(zoom))
		_material.set_shader_parameter("land_natural", land_natural_for(zoom, land_style))


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
		Mode.CONSTRUCTION:
			for type in Economy.building_ids():
				list.append([type, Economy.cfg.buildings[type].name])
		Mode.MILITARY:
			list = [[MIL_CONTROL, "Control"], [MIL_FRONT, "Front line"], [MIL_STRENGTH, "Strength"], [MIL_SUPPLY, "Supply"]]
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
	_material.set_shader_parameter("land_on", land_style != "off" and mode in LAND_TEXTURE_MODES)
	_material.set_shader_parameter("occupation_stripes", mode == Mode.POLITICAL)
	_material.set_shader_parameter("diplomacy", mode == Mode.DIPLOMACY)
	_material.set_shader_parameter("zone_paint", mode in NAVAL_MODES)
	_material.set_shader_parameter("hatch_marks", mode == Mode.BLOCKADE)
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


func _queue_military_repaint() -> void:
	if mode != Mode.MILITARY or submode in [MIL_CONTROL, MIL_FRONT] or _repaint_queued:
		return
	_repaint_queued = true
	_deferred_military_repaint.call_deferred()


func _deferred_military_repaint() -> void:
	_repaint_queued = false
	if mode == Mode.MILITARY:
		repaint()


func _queue_naval_repaint() -> void:
	if not mode in NAVAL_MODES or _repaint_queued:
		return
	_repaint_queued = true
	_deferred_naval_repaint.call_deferred()


func _deferred_naval_repaint() -> void:
	_repaint_queued = false
	if mode in NAVAL_MODES:
		repaint()


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
	if mode == Mode.MILITARY:
		_count_forces()
	for id in range(1, count):
		@warning_ignore("integer_division")
		var px := Vector2i(id % LOOKUP_WIDTH, id / LOOKUP_WIDTH)
		_owner_image.set_pixelv(px, GameState.owner_color(id))
		_lookup_image.set_pixelv(px, _paint_color(id, values[id]))
	_lookup_texture.update(_lookup_image)
	_owner_texture.update(_owner_image)
	if mode == Mode.DIPLOMACY:
		_paint_diplomacy_marks()
	if mode in NAVAL_MODES:
		_paint_zones()
	if mode == Mode.BLOCKADE:
		_paint_blockade_marks()


## Tints every sea zone by who holds it (contested zones dark red; zones nobody holds stay clear).
func _paint_zones() -> void:
	_zone_image.fill(Color(0, 0, 0, 0))
	for zone: int in GameState.sea_control:
		var c: Dictionary = GameState.sea_control[zone]
		var color := CONTESTED_COLOR
		if not c.contested and not c.holders.is_empty():
			color = GameState.nations[c.holders[0]].color
		_zone_image.set_pixel(zone, 0, Color(color, 0.62 if mode == Mode.SEA_CONTROL else 0.45))
	_zone_texture.update(_zone_image)


## Hatches the coastal provinces of nations whose trade is being cut off.
func _paint_blockade_marks() -> void:
	for id in range(1, MapData.provinces.size()):
		@warning_ignore("integer_division")
		var px := Vector2i(id % LOOKUP_WIDTH, id / LOOKUP_WIDTH)
		var n: Nation = GameState.nations[GameState.province_owner[id]]
		var hatched := n.blockade >= 0.05 and not MapData.zones_of_port(id).is_empty()
		_marks_image.set_pixelv(px, BLOCKADE_COLOR.lightened(0.25) if hatched else Color(0, 0, 0, 0))
	_marks_texture.update(_marks_image)


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
			return amount if amount >= Economy.cfg.materials.min_deposit else 0.0
		Mode.INCOME:
			# Tax the province yields each month.
			return Fmt.monthly(GameState.province_gdp[id]) * GameState.nations[GameState.province_owner[id]].tax_rate
		Mode.POPULATION:
			return float(GameState.province_population[id])
		Mode.BUILDINGS:
			var levels := 0
			for type in GameState.province_buildings[id]:
				if submode == ALL_BUILDINGS:
					if not str(Economy.cfg.buildings[type].get("requires", "")).begins_with("deposit:") and not Economy.cfg.buildings[type].get("slot", false):
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
	if mode == Mode.BLOCKADE:
		return NO_DATA_COLOR.lerp(BLOCKADE_COLOR, clampf(GameState.nations[GameState.province_owner[id]].blockade, 0.0, 1.0))
	if mode == Mode.SEA_CONTROL:
		return NO_DATA_COLOR.lerp(GameState.owner_color(id), 0.55)
	if mode == Mode.CONSTRUCTION:
		return construction_color(id, submode)
	if mode == Mode.MILITARY:
		return military_color(id)
	if mode == Mode.POLITICAL:
		# Who holds the ground. Political stripes occupied provinces with the owner's colour
		# (in the shader).
		return GameState.nations[GameState.province_controller[id]].color
	if mode != Mode.RESOURCES and not MODE_COLORS.has(mode):
		return GameState.owner_color(id)
	if value <= 0.0:
		return NO_DATA_COLOR
	return NO_DATA_COLOR.lerp(_mode_color(), 0.25 + 0.75 * _scale(value))


## Men of the armies standing in each province (embarked ones are at sea).
func _count_forces() -> void:
	_men_at.clear()
	for a: Army in GameState.armies.values():
		if a.embarked():
			continue
		var level := Intel.level(GameState, a)
		if level == Intel.HIDDEN:
			continue
		var men := Intel.men_seen(GameState, a)
		_men_at[a.province] = _men_at.get(a.province, 0.0) + men
	_max_value = 0.0
	for id: int in _men_at:
		_max_value = maxf(_max_value, _men_at[id])


## Whether a province lies on a front: held by a nation at war with the holder of a neighbour.
func on_front(id: int) -> bool:
	var holder: String = GameState.province_controller[id]
	for n in Military.neighbors(id):
		var other: String = GameState.province_controller[n]
		if other != holder and GameState.at_war(holder, other):
			return true
	return false


## What a province shows in Military mode, by variant.
func military_color(id: int) -> Color:
	var held: Color = GameState.nations[GameState.province_controller[id]].color
	match submode:
		MIL_FRONT:
			return held.lerp(FRONT_HOT, 0.65) if on_front(id) else held.darkened(0.45)
		MIL_STRENGTH:
			var men: float = _men_at.get(id, 0.0)
			return NO_DATA_COLOR.darkened(0.45) if men <= 0.0 else NO_DATA_COLOR.lerp(STRENGTH_COLOR, 0.25 + 0.75 * _scale(men))
		MIL_SUPPLY:
			return supply_color(id)
	return held


## What a province shows in the Supply variant: how well the player's armies would be supplied standing there. Green is
## ground tied to the homeland; yellow through amber is ground in supply range, the nearer the range's end the more amber;
## red is beyond it, where an army suffers attrition.
func supply_color(id: int) -> Color:
	var tag := GameState.player_tag
	if tag == "" or not GameState.nations.has(tag):
		return NO_DATA_COLOR
	var cost := Military.supply_cost(GameState, tag, id)
	if cost == 0.0:
		return SUPPLY_HOME
	if cost == INF:
		return SUPPLY_NONE
	var reach: float = Military.cfg.supply.range + float(Military.cfg.cities.supply_range) * Military.city_aura(GameState, tag, id)
	return SUPPLY_NEAR.lerp(SUPPLY_FAR, clampf(cost / maxf(reach, 0.1), 0.0, 1.0))


## What a province shows in Construction mode for one kind of building: dark if it is not the
## player's; green where one can be built; blue where it already stands and no more can; teal
## where it stands and another can still be built; grey where it cannot be built.
func construction_color(id: int, type: String) -> Color:
	var tag := GameState.player_tag
	if GameState.province_owner[id] != tag or not Economy.cfg.buildings.has(type):
		return CONSTRUCT_OTHER
	var built: int = GameState.province_buildings[id].get(type, 0)
	var can := Economy.build_problem(GameState, tag, id, type, false).is_empty()
	if built > 0:
		return CONSTRUCT_BOTH if can else CONSTRUCT_HAVE.darkened(0.35 * (1.0 - minf(built / 4.0, 1.0)))
	return CONSTRUCT_BUILD if can else CONSTRUCT_BLOCKED


## 0..1 position of a value on the mode's color scale: deposits span orders of magnitude, so
## they use a log scale; everything else uses a square root so small values stay visible.
func _scale(value: float) -> float:
	if _max_value <= 0.0:
		return 0.0
	if mode == Mode.RESOURCES:
		var floor_value: float = Economy.cfg.materials.min_deposit
		return clampf(log(maxf(value, floor_value) / floor_value) / maxf(log(_max_value / floor_value), 0.001), 0.0, 1.0)
	return clampf(sqrt(value / _max_value), 0.0, 1.0)


func _mode_color() -> Color:
	if mode == Mode.RESOURCES:
		return Color(Economy.cfg.resources[submode].color)
	return MODE_COLORS[mode]


## What the legend should show for the current mode: a title, the ends of the color scale,
## and its color. Empty for modes that are not shaded.
func legend() -> Dictionary:
	if mode == Mode.BLOCKADE:
		return {"title": "Trade cut off by blockade", "low": "none", "high": "all", "from": NO_DATA_COLOR, "to": BLOCKADE_COLOR}
	if mode == Mode.DIPLOMACY:
		return {"title": "Opinion of %s" % GameState.nations[diplomacy_viewpoint()].display_name if GameState.nations.has(diplomacy_viewpoint()) else "Opinion",
				"low": "hostile", "high": "friendly", "from": HOSTILE_COLOR, "to": FRIENDLY_COLOR}
	if mode == Mode.CONSTRUCTION:
		return {"title": "Build: %s" % Economy.cfg.buildings[submode].name.to_lower() if Economy.cfg.buildings.has(submode) else "Construction",
				"swatches": [
					[CONSTRUCT_BUILD, "can build"],
					[CONSTRUCT_BOTH, "built, room for more"],
					[CONSTRUCT_HAVE, "built, full"],
					[CONSTRUCT_BLOCKED, "cannot build"],
					[CONSTRUCT_OTHER, "not yours"],
				]}
	if mode == Mode.MILITARY:
		match submode:
			MIL_FRONT:
				return {"title": "Front line", "swatches": [[FRONT_HOT, "held next to an enemy"], [NO_DATA_COLOR.darkened(0.45), "rear"]]}
			MIL_SUPPLY:
				return {"title": "Supply for your armies", "swatches": [[SUPPLY_HOME, "tied to home: full supply"], [SUPPLY_NEAR.lerp(SUPPLY_FAR, 0.5), "in range, thinner with distance"], [SUPPLY_NONE, "out of supply: attrition"]]}
			MIL_STRENGTH:
				return {"title": "Men stationed", "low": "none", "high": Fmt.people(_max_value) if _max_value > 0.0 else "none",
						"from": NO_DATA_COLOR.lerp(STRENGTH_COLOR, 0.25), "to": STRENGTH_COLOR}
		return {}
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
	select_zone(0)
	province_selected.emit(id)


## Selects a sea zone (0 clears it). A zone and a province are never selected together.
func select_zone(zone: int) -> void:
	if zone == selected_zone:
		return
	selected_zone = zone
	_material.set_shader_parameter("selected_zone", zone)
	if zone > 0 and selected_id != 0:
		selected_id = 0
		_material.set_shader_parameter("selected_id", 0)
		province_selected.emit(0)
	sea_zone_selected.emit(zone)


func set_show_zones(on: bool) -> void:
	show_zones = on
	_material.set_shader_parameter("show_zones", on)


func _box_rect() -> Rect2:
	return Rect2(_press_world, get_global_mouse_position() - _press_world).abs()


## The left button came up: a drag selects armies in the box, a click selects the province.
## Whether the pointer is over a control that takes the mouse (a window, a panel, a menu).
func _over_interface() -> bool:
	var over := get_viewport().gui_get_hovered_control()
	return over != null and over.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _finish_press(_screen_pos: Vector2) -> void:
	var was_box := _boxing
	_pressing = false
	_boxing = false
	if was_box:
		get_tree().call_group("army_layer", "set_box", Rect2())
		box_selected.emit(_box_rect(), Input.is_key_pressed(KEY_SHIFT))
	elif _over_interface():
		return  # the click ended over a window or panel: it is theirs, not the map's
	else:
		var layer := get_tree().get_first_node_in_group("army_layer")
		var fleet_layer := get_tree().get_first_node_in_group("fleet_layer")
		var battle: int = layer.pick_battle_at(get_global_mouse_position()) if layer != null else 0
		var hit: int = layer.pick_at(get_global_mouse_position()) if layer != null else 0
		var sea_battle: int = fleet_layer.pick_battle_at(get_global_mouse_position()) if fleet_layer != null else 0
		var fleets: Array[int] = fleet_layer.pick_at(get_global_mouse_position()) if fleet_layer != null else []
		if battle > 0:
			battle_clicked.emit(battle)
		elif sea_battle > 0:
			sea_battle_clicked.emit(sea_battle)
		elif not fleets.is_empty():
			fleets_clicked.emit(fleets, Input.is_key_pressed(KEY_SHIFT))
		elif hit > 0:
			army_clicked.emit(hit, Input.is_key_pressed(KEY_SHIFT))
		else:
			var id := maxi(_province_under_mouse(), 0)
			var zone := _zone_under_mouse() if id == 0 else 0
			if zone > 0:
				select_zone(zone)
			else:
				select(id)


func _province_under_mouse() -> int:
	var px := Vector2i(to_local(get_global_mouse_position()).floor())
	return MapData.province_at_pixel(px)


func _zone_under_mouse() -> int:
	return MapData.sea_zone_at_pixel(Vector2i(to_local(get_global_mouse_position()).floor()))


## The small tip that follows the mouse in the Diplomacy mode: how the nation under it stands with
## the viewpoint nation.
var _tip_layer: CanvasLayer
var _tip := PanelContainer.new()
var _tip_label := Label.new()


## Whether armies are selected, so that a province under the mouse would be an order.
func _orders_selected() -> bool:
	var panel := get_tree().get_first_node_in_group("military_panel")
	return panel != null and panel.has_method("selected_ids") and not panel.selected_ids().is_empty() and GameState.player_tag != ""


var _tip_key := ""


func _show_diplomacy_tip(id: int) -> void:
	var text := ""
	if id > 0 and not _over_interface():
		# The order preview is a search over the map: worked out again only when the province or the selection changes.
		var panel := get_tree().get_first_node_in_group("military_panel")
		var key := "%d|%s|%d" % [id, str(panel.selected_ids()) if panel != null and mode != Mode.DIPLOMACY else "", Clock.days_elapsed]
		if _tip_layer != null and _tip.visible and key == _tip_key:
			_place_tip()
			return
		_tip_key = key
		text = _diplomacy_tip_text(id) if mode == Mode.DIPLOMACY else _order_tip_text(id)
	if text.is_empty():
		if _tip_layer != null:
			_tip.visible = false
		return
	if _tip_layer == null:
		_tip_layer = CanvasLayer.new()
		_tip_layer.layer = 90
		add_child(_tip_layer)
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_label.add_theme_font_size_override("font_size", 12)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.07, 0.1, 0.92)
		box.border_color = Color(0.5, 0.45, 0.3)
		box.set_border_width_all(1)
		box.set_content_margin_all(6)
		_tip.add_theme_stylebox_override("panel", box)
		_tip.add_child(_tip_label)
		_tip_layer.add_child(_tip)
	_tip_label.text = text
	_tip.reset_size()
	_tip.visible = true
	_place_tip()


func _place_tip() -> void:
	var view := get_viewport().get_visible_rect().size
	var at := get_viewport().get_mouse_position() + Vector2(16, 18)
	at.x = minf(at.x, view.x - _tip.size.x - 4.0)
	at.y = minf(at.y, view.y - _tip.size.y - 4.0)
	_tip.position = at


## What an order to this province would do, when armies are selected: the road, the date of arrival, the supply on the
## way and what is known of the enemy there.
func _order_tip_text(id: int) -> String:
	var panel := get_tree().get_first_node_in_group("military_panel")
	if panel == null or not panel.has_method("selected_ids") or GameState.player_tag == "":
		return ""
	var ids: Array[int] = panel.selected_ids()
	if ids.is_empty():
		return ""
	return order_tip_for(ids, id)


## The text of the order preview for these armies and a province ("" when there is nothing to say).
func order_tip_for(ids: Array, id: int) -> String:
	var p := Military.order_preview(GameState, ids, id)
	if not p.ok:
		return {"no_route": "No road there for these armies."}.get(p.reason, "")
	var lines: PackedStringArray = ["%s: %d days, arriving %s" % [MapData.provinces[id].name, roundi(p.days), p.eta]]
	if p.unsupplied == 0:
		lines.append("In supply all the way")
	elif p.ends_supplied:
		lines.append("%d of %d stages out of supply" % [p.unsupplied, p.hops])
	else:
		lines.append("Out of supply there (%d of %d stages): attrition" % [p.unsupplied, p.hops])
	if p.enemy_seen:
		lines.append("Enemy seen: %s to %s men" % [Fmt.people(p.enemy.x), Fmt.people(p.enemy.y)])
		lines.append("Odds %.1f to %.1f (men only; terrain unknown)" % [p.odds.x, p.odds.y])
	return "\n".join(lines)


## Name, opinion and treaties of the nation owning a province, as the viewpoint nation sees it.
func _diplomacy_tip_text(id: int) -> String:
	var tag: String = GameState.province_owner[id]
	var me := diplomacy_viewpoint()
	if not GameState.nations.has(tag) or not GameState.nations.has(me):
		return ""
	var lines: PackedStringArray = [GameState.nations[tag].display_name]
	if tag == me:
		lines.append("Yourself" if me == GameState.player_tag else "The viewpoint nation")
		return "\n".join(lines)
	var r := Diplomacy.relation(GameState, me, tag)
	lines.append("Opinion %s (%+d)" % [load("res://scripts/ui/diplomacy_panel.gd").mood(r), roundi(r)])
	if GameState.at_war(me, tag):
		lines.append("At war")
	for t in Diplomacy.treaties_between(GameState, me, tag):
		var label: String = Diplomacy.cfg.treaties[t.kind].label
		if t.terms.get("entente", false):
			label += " (entente)"
		elif t.kind == "guarantee":
			label += " (%s guarantees %s)" % [GameState.nations[t.a].display_name, GameState.nations[t.b].display_name]
		elif t.kind == "passage":
			label += " (%s lets %s cross)" % [GameState.nations[t.a].display_name, GameState.nations[t.b].display_name]
		lines.append(label)
	var bloc := Diplomacy.bloc_name(GameState, tag)
	if bloc != "":
		lines.append("Bloc: " + bloc)
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z 			and not event.ctrl_pressed and not event.alt_pressed:
		set_show_zones(not show_zones)
	elif event is InputEventMouseMotion:
		var zone := _zone_under_mouse()
		if zone != hover_zone:
			hover_zone = zone
			_material.set_shader_parameter("hover_zone", zone)
		var id := maxi(_province_under_mouse(), 0)
		_show_diplomacy_tip(id)
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
		elif _zone_under_mouse() > 0:
			zone_ordered.emit(_zone_under_mouse())


## Stripes the provinces plans of attack mean to take: province id -> colour (empty: none). Only repaints when it changes.
func set_plan_zone(zone: Dictionary) -> void:
	if _plans_image == null:
		return
	var signature := []
	for id in zone:
		signature.append([id, zone[id]])
	signature.sort()
	if signature == _plan_signature:
		return
	_plan_signature = signature
	_plans_image.fill(Color(0, 0, 0, 0))
	for id: int in zone:
		_plans_image.set_pixelv(Vector2i(id % LOOKUP_WIDTH, id / LOOKUP_WIDTH), Color(zone[id], 1.0))
	_plans_texture.update(_plans_image)
	_material.set_shader_parameter("plan_stripes", not zone.is_empty())
