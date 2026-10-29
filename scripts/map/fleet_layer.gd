class_name FleetLayer
extends Node2D
## Draws fleets: a banner per nation at each place it has ships (a sea zone, or beside the
## harbour town when in port) with a ship symbol, the number of squadrons, the men it carries
## and its standing orders; the routes of fleets under sail; and a crossed-swords icon on a
## zone where a battle is being fought. Markers keep a constant size on screen whatever the zoom.

const BANNER := Vector2(58, 20)
const GAP := 3.0
const SELECT_COLOR := Color(1.0, 0.95, 0.4)
const BATTLE_COLOR := Color(0.95, 0.25, 0.2)
const ROUTE_COLOR := Color(0.8, 0.95, 1.0, 0.6)
## Map pixels of open water a harbour spot keeps round it (see harbour_spot).
const HARBOUR_CLEAR := 10.0
const MISSION_LETTERS := {"station": "S", "patrol": "P", "blockade": "B", "escort": "E", "raid": "R"}

## Ids of the fleets the player has selected.
var selected: Array[int] = []

var _font: Font = ThemeDB.fallback_font
var _zoom := 0.0
## While true the banners are not drawn: each is listed in `markers` instead, for the 3D map to stand
## up as models ({tag, squadrons, fleets, men, picked, fighting, pos in map pixels}).
var markers_only := false:
	set(value):
		markers_only = value
		queue_redraw()
var markers: Array = []
var _collecting := false
## Harbour spots worked out so far: province id -> Vector2.
static var _harbours := {}


func _ready() -> void:
	if card_only:
		_zoom = 1.0
		return
	add_to_group("fleet_layer")
	z_index = 4
	GameState.fleets_changed.connect(queue_redraw)
	GameState.armies_changed.connect(queue_redraw)
	GameState.scenario_loaded.connect(queue_redraw)
	GameState.sea_battle_fought.connect(func(_z: int, _t: Array) -> void: queue_redraw())


func set_selection(ids: Array[int]) -> void:
	selected = ids
	queue_redraw()


func _process(_delta: float) -> void:
	if card_only:
		return
	var camera := get_viewport().get_camera_2d()
	if camera and camera.zoom.x != _zoom:
		_zoom = camera.zoom.x
		queue_redraw()


# ------------------------------------------------------------------ layout

## Where a fleet is drawn, in map pixels: its port's harbour spot, or its place at sea (between
## two zones when it is sailing).
static func position_of(f: Fleet, px := 1.0) -> Vector2:
	if f.port > 0:
		return harbour_spot(f.port)
	if f.zone <= 0:
		return Vector2.ZERO
	var here: Vector2 = MapData.sea_zones[f.zone].center
	if f.path.is_empty():
		return here
	var next: Vector2 = MapData.sea_zones[f.path[0]].center
	var total := maxf(Navy.zone_days(f.speed(), f.zone, f.path[0]), 1.0)
	var done := clampf(1.0 - f.move_days_left / total, 0.0, 1.0)
	return here.lerp(next, done)


## Where the ships of a port lie, in map pixels: on the water off its harbour town (the province's biggest city, or
## its centre), in the port's own sea zone where it can be, with HARBOUR_CLEAR of open water round it (less in narrow
## waters), so that a
## fleet in port is drawn at sea, not on the land. Worked out once for each port.
static func harbour_spot(province: int) -> Vector2:
	if _harbours.has(province):
		return _harbours[province]
	var origin: Vector2 = MapData.provinces[province].center
	var towns: Array = GameState.cities_by_province.get(province, [])
	if not towns.is_empty():
		origin = towns[0].pos
	var zones: Array[int] = MapData.zones_of_port(province)
	var best := origin
	# The port's own zone with open water round it first; then any zone; then narrower water (a river mouth, a strait).
	for pass_ in [[true, HARBOUR_CLEAR], [false, HARBOUR_CLEAR], [false, 5.0], [false, 1.5]]:
		var own_zone_only: bool = pass_[0]
		var clear: float = pass_[1]
		var found := false
		for r in range(3, 240, 3):
			for i in 32:
				var dir := Vector2.from_angle(TAU * i / 32.0)
				var p := origin + dir * r
				if not _open_water(p, clear):
					continue
				if own_zone_only and not zones.is_empty() and not zones.has(MapData.sea_zone_at_pixel(Vector2i(p.floor()))):
					continue
				best = p
				found = true
				break
			if found:
				break
		if found:
			break
	_harbours[province] = best
	return best


## Whether the water at `p` is open: `p` and a ring of points `clear` map pixels round it are all sea.
static func _open_water(p: Vector2, clear: float) -> bool:
	if MapData.province_at_pixel(Vector2i(p.floor())) != MapData.SEA:
		return false
	for i in 12:
		var q := p + Vector2.from_angle(TAU * i / 12.0) * clear
		if MapData.province_at_pixel(Vector2i(q.floor())) != MapData.SEA:
			return false
	return true


## One entry per (place, nation): {rect, tag, fleets, centre}. Places are zones for fleets at
## sea and provinces for fleets in port; sailing fleets each stand on their own.
func _groups(px: float) -> Array:
	var places := {}
	for f: Fleet in GameState.fleets.values():
		var key := ""
		if f.port > 0:
			key = "p%d" % f.port
		elif f.path.is_empty() or f.fighting:
			key = "z%d" % f.zone
		else:
			key = "f%d" % f.id
		if not places.has(key):
			places[key] = []
		places[key].append(f)
	var out := []
	var size := BANNER * px
	var gap := GAP * px
	var keys := places.keys()
	keys.sort()
	for key: String in keys:
		var here: Array = places[key]
		var tags: Array = []
		for f: Fleet in here:
			if not tags.has(f.tag):
				tags.append(f.tag)
		tags.sort()
		var first: Fleet = here[0]
		var centre := position_of(first, px)
		var top := centre.y - (size.y * tags.size() + gap * (tags.size() - 1)) * 0.5
		for i in tags.size():
			var mine: Array[Fleet] = []
			for f: Fleet in here:
				if f.tag == tags[i]:
					mine.append(f)
			mine.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.id < b.id)
			out.append({"rect": Rect2(Vector2(centre.x - size.x * 0.5, top + i * (size.y + gap)), size),
					"tag": tags[i], "fleets": mine, "centre": centre})
	return out


## The banners as markers (see `markers_only`), worked out now rather than at the next redraw.
func collect_markers() -> Array:
	markers.clear()
	_collecting = true
	var px := 1.0 / maxf(_zoom, 0.05)
	for g in _groups(px):
		_draw_group(g, px)
	_collecting = false
	return markers


## Ids of the fleets whose banner is under a map position (empty if none).
func pick_at(world_pos: Vector2) -> Array[int]:
	var out: Array[int] = []
	for g in _groups(1.0 / maxf(_zoom, 0.05)):
		if (g.rect as Rect2).has_point(world_pos):
			for f: Fleet in g.fleets:
				out.append(f.id)
			return out
	return out


## Ids of the fleets of a nation standing inside a map rectangle.
static func fleets_in_rect(rect: Rect2, tag: String) -> Array[int]:
	var out: Array[int] = []
	for f: Fleet in Navy.fleets_of(GameState, tag):
		if rect.has_point(position_of(f)):
			out.append(f.id)
	return out


func _battle_icon_rect(zone: int, px: float) -> Rect2:
	var c: Vector2 = MapData.sea_zones[zone].center
	var half := 11.0 * px
	var centre := Vector2(c.x - (BANNER.x * 0.5 + 16.0) * px, c.y)
	return Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)


## Zone of the sea battle icon under a map position (0 if none).
func pick_battle_at(world_pos: Vector2) -> int:
	var px := 1.0 / maxf(_zoom, 0.05)
	for zone: int in GameState.sea_battles:
		if _battle_icon_rect(zone, px).grow(2.0 * px).has_point(world_pos):
			return zone
	return 0


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if card_only:
		_paint_card()
		return
	var px := 1.0 / maxf(_zoom, 0.05)
	_draw_routes(px)
	markers.clear()
	for g in _groups(px):
		_draw_group(g, px)
	_draw_battle_icons(px)


func _draw_group(g: Dictionary, px: float) -> void:
	var rect: Rect2 = g.rect
	var color: Color = GameState.nations[g.tag].color
	var squadrons := 0
	var men := 0.0
	var picked := false
	var fighting := false
	var mission := ""
	var mixed := false
	var classes := {}
	for f: Fleet in g.fleets:
		for ship: Ship in f.ships:
			classes[ship.type] = int(classes.get(ship.type, 0)) + 1
		squadrons += f.ships.size()
		men += Navy.men_aboard(GameState, f)
		picked = picked or selected.has(f.id)
		fighting = fighting or f.fighting
		if mission.is_empty():
			mission = f.mission
		elif mission != f.mission:
			mixed = true
	if markers_only or _collecting:
		markers.append({"in_port": (g.fleets[0] as Fleet).port > 0, "tag": g.tag, "squadrons": squadrons, "fleets": g.fleets.size(), "men": men, "picked": picked,
				"fighting": fighting, "pos": rect.get_center(), "classes": classes, "mission": mission, "mixed": mixed, "aboard": men})
		return
	_draw_fleet_banner(rect, px, color, squadrons, g.fleets.size(), picked, fighting, mission, mixed, men)


func _draw_fleet_banner(rect: Rect2, px: float, color: Color, squadrons: int, fleets: int, picked: bool, fighting: bool, mission: String, mixed: bool, men: float) -> void:
	draw_rect(rect, color)
	var frame := Rect2(rect.position + Vector2(2, 2) * px, Vector2(rect.size.y * 1.25 - 4.0 * px, rect.size.y - 4.0 * px))
	draw_rect(frame, Color(1, 1, 1, 0.92))
	_draw_ship(frame, px)
	var text_color := Color.WHITE if color.get_luminance() < 0.55 else Color.BLACK
	var label := "%d" % squadrons
	if fleets > 1:
		label += " ×%d" % fleets
	var text_x := frame.end.x + 2.0 * px
	MapText.draw(self, _font, Vector2(text_x, rect.end.y - 5.0 * px), label, HORIZONTAL_ALIGNMENT_CENTER,
			rect.end.x - text_x - 1.0 * px, 11, text_color, px)
	var border := SELECT_COLOR if picked else (BATTLE_COLOR if fighting else Color(0, 0, 0, 0.85))
	draw_rect(rect, border, false, (2.5 if picked or fighting else 1.5) * px)
	if mission != "" and not mixed and mission != "station":
		_pill(MISSION_LETTERS.get(mission, "?"), Vector2(rect.end.x + 8.0 * px, rect.position.y + 6.0 * px), px, Color.WHITE, 9)
	if men > 0.0:
		_pill("%dk aboard" % roundi(men / 1000.0), Vector2(rect.get_center().x, rect.end.y + 8.0 * px), px, Color(0.9, 0.85, 0.5), 9)
	if fighting:
		MapText.draw(self, _font, Vector2(rect.end.x + 2.0 * px, rect.position.y + 12.0 * px), "⚔", HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 14, BATTLE_COLOR, px)


## A card of one marker (see ArmyLayer.card_only).
const CARD_SIZE := Vector2(170, 72)
const CARD_BANNER := Rect2(Vector2(56, 16), BANNER)
var card_only := false
var card := {}


func set_card(entry: Dictionary) -> void:
	card = entry
	queue_redraw()


func _paint_card() -> void:
	if card.is_empty():
		return
	_draw_fleet_banner(CARD_BANNER, 1.0, GameState.nations[card.tag].color, card.squadrons, card.fleets, card.picked, card.fighting,
			card.get("mission", ""), card.get("mixed", false), card.get("aboard", 0.0))


## A small ship in side view.
func _draw_ship(r: Rect2, px: float) -> void:
	var ink := Color(0.05, 0.05, 0.08)
	var c := r.get_center()
	var w := r.size.x * 0.8
	var h := r.size.y * 0.34
	var hull := PackedVector2Array([
		Vector2(c.x - w * 0.5, c.y), Vector2(c.x + w * 0.5, c.y),
		Vector2(c.x + w * 0.34, c.y + h), Vector2(c.x - w * 0.4, c.y + h)])
	draw_colored_polygon(hull, ink)
	draw_rect(Rect2(c.x - w * 0.16, c.y - h * 0.9, w * 0.32, h * 0.9), ink)
	draw_line(Vector2(c.x, c.y - h * 0.9), Vector2(c.x, c.y - h * 1.7), ink, 1.4 * px)


func _draw_routes(px: float) -> void:
	for f: Fleet in GameState.fleets.values():
		if f.tag != GameState.player_tag or not (f.is_moving() or f.landing > 0):
			continue
		var picked := selected.has(f.id)
		var color := SELECT_COLOR if picked else ROUTE_COLOR
		var from := position_of(f, px)
		var days := maxf(f.move_days_left, 0.0)
		var prev := f.zone
		for i in f.path.size():
			var to: Vector2 = MapData.sea_zones[f.path[i]].center
			draw_dashed_line(from, to, color, (2.5 if picked else 1.5) * px, 6.0 * px)
			if i > 0:
				days += Navy.zone_days(f.speed(), prev, f.path[i])
			prev = f.path[i]
			from = to
		if f.dest_port > 0:
			var port: Vector2 = harbour_spot(f.dest_port)
			draw_dashed_line(from, port, color, (2.5 if picked else 1.5) * px, 6.0 * px)
			from = port
			days += Navy.cfg.port_days
		elif f.landing > 0:
			var coast: Vector2 = MapData.provinces[f.landing].center
			draw_dashed_line(from, coast, Color(0.95, 0.8, 0.4, 0.9), (2.5 if picked else 1.5) * px, 4.0 * px)
			from = coast
		draw_circle(from, (5.0 if picked else 3.5) * px, color)
		if picked or f.landing > 0:
			_pill("%dd" % roundi(days), from + Vector2(0, -12.0 * px), px, color, 10)


func _draw_battle_icons(px: float) -> void:
	for zone: int in GameState.sea_battles:
		var rect := _battle_icon_rect(zone, px)
		var c := rect.get_center()
		draw_circle(c, 11.0 * px, Color(0.62, 0.12, 0.1))
		draw_arc(c, 11.0 * px, 0.0, TAU, 24, Color.WHITE, 1.6 * px, true)
		var w := 2.0 * px
		draw_line(c + Vector2(-6.5, 6.5) * px, c + Vector2(6.5, -6.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(-6.5, -6.5) * px, c + Vector2(6.5, 6.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(-7.5, 2.0) * px, c + Vector2(-2.0, 7.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(7.5, 2.0) * px, c + Vector2(2.0, 7.5) * px, Color.WHITE, w)
		var day: int = Clock.days_elapsed - GameState.sea_battles[zone].start_day + 1
		_pill("day %d" % day, c + Vector2(0, 18.0 * px), px, Color.WHITE, 9)


func _pill(text: String, at: Vector2, px: float, color: Color, font_px: int) -> void:
	var size := MapText.size_of(_font, text, font_px, px)
	var pad := 3.0 * px
	var rect := Rect2(at - Vector2(size.x * 0.5 + pad, size.y * 0.5 + pad * 0.5), size + Vector2(pad * 2.0, pad))
	draw_rect(rect, Color(0.05, 0.07, 0.1, 0.82))
	MapText.draw(self, _font, Vector2(rect.position.x + pad, rect.end.y - pad - size.y * 0.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px, Color(color, 1.0), px)
