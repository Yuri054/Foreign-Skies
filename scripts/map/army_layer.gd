extends Node2D
## Draws armies as banners (a nation-coloured flag with a NATO-style symbol, men in
## thousands and a size mark), the player's fronts, the routes of marching armies with the
## days each province takes, a preview of where a right click would send the selection, and
## the drag-selection box. Markers keep a constant size on screen whatever the zoom.

const BANNER := Vector2(62, 22)
const CARD_ROWS := 4
const GAP := 3.0
const SELECT_COLOR := Color(1.0, 0.95, 0.4)
const BATTLE_COLOR := Color(0.95, 0.25, 0.2)
const PREVIEW_COLOR := Color(0.85, 0.95, 1.0, 0.85)
const DRAFT_COLOR := Color(0.4, 0.95, 1.0)
const FRONT_COLORS := [Color(0.95, 0.55, 0.2), Color(0.35, 0.85, 0.5), Color(0.75, 0.5, 0.95), Color(0.95, 0.4, 0.55), Color(0.4, 0.75, 0.95)]  # the same as MapView.FRONT_COLORS

## Ids of the armies the player has selected.
var selected: Array[int] = []

var _font: Font = ThemeDB.fallback_font
var _zoom := 0.0
var _box := Rect2()
var _draft: Array[int] = []
var _selected_front := 0
var _hover := 0
## The selected province, when it holds several armies: they are fanned out one by one.
var _expanded := 0
var _preview: Array[int] = []
var _preview_etas: Array[float] = []
var _preview_from := 0
## Front labels waiting to be drawn over the banners: [front, position, colour, chosen].
var _labels: Array = []


func _ready() -> void:
	add_to_group("army_layer")
	z_index = 5
	GameState.armies_changed.connect(queue_redraw)
	GameState.fronts_changed.connect(queue_redraw)
	GameState.scenario_loaded.connect(queue_redraw)


func set_selection(ids: Array[int]) -> void:
	selected = ids
	_update_preview()
	queue_redraw()


## The province the player selected. If it holds more than one army they are drawn
## individually beside it, each clickable.
func set_expanded(province: int) -> void:
	_expanded = province
	queue_redraw()


## Where the clickable icon of the battle in a province is: to the left of its banners.
func _battle_icon_rect(province: int, px: float) -> Rect2:
	var c: Vector2 = MapData.provinces[province].center
	var half := 11.0 * px
	var centre := Vector2(c.x - (BANNER.x * 0.5 + 16.0) * px, c.y)
	return Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)


## Province of the battle icon under a map position (0 if none).
func pick_battle_at(world_pos: Vector2) -> int:
	var px := 1.0 / maxf(_zoom, 0.05)
	for province: int in GameState.engagements:
		if not Intel.sees_province(GameState, province):
			continue
		if _battle_icon_rect(province, px).grow(2.0 * px).has_point(world_pos):
			return province
	return 0


func _draw_battle_icons(px: float) -> void:
	for province: int in GameState.engagements:
		if not Intel.sees_province(GameState, province):
			continue
		var rect := _battle_icon_rect(province, px)
		var c := rect.get_center()
		draw_circle(c, 11.0 * px, Color(0.62, 0.12, 0.1))
		draw_arc(c, 11.0 * px, 0.0, TAU, 24, Color.WHITE, 1.6 * px, true)
		var w := 2.0 * px
		# Two crossed swords: blades corner to corner, a short guard across each.
		draw_line(c + Vector2(-6.5, 6.5) * px, c + Vector2(6.5, -6.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(-6.5, -6.5) * px, c + Vector2(6.5, 6.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(-7.5, 2.0) * px, c + Vector2(-2.0, 7.5) * px, Color.WHITE, w)
		draw_line(c + Vector2(7.5, 2.0) * px, c + Vector2(2.0, 7.5) * px, Color.WHITE, w)
		var day: int = Clock.days_elapsed - GameState.engagements[province].start_day + 1
		_pill("day %d" % day, c + Vector2(0, 18.0 * px), px, Color.WHITE, 9)


## Id of the army whose fanned-out banner is under a map position (0 if none).
func pick_at(world_pos: Vector2) -> int:
	for entry in _expanded_layout(1.0 / maxf(_zoom, 0.05)):
		if (entry.rect as Rect2).has_point(world_pos):
			return entry.army.id
	return 0


func set_hover(province: int) -> void:
	var changed := province != _hover
	_hover = province
	_update_preview()
	if changed:
		queue_redraw()


## The armies the hover card describes: those drawn in the hovered province, the player's
## first, when it is not the one fanned out already (the fanned banners show the same).
func card_armies() -> Array[Army]:
	var list: Array[Army] = []
	if _hover <= 0 or _hover == _expanded and _expanded_armies().size() >= 2:
		return list
	for a: Army in Military.armies_at(GameState, _hover):
		if seen(a) == Intel.EXACT:
			list.append(a)
	list.sort_custom(func(x: Army, y: Army) -> bool:
		var mine_x: bool = x.tag == GameState.player_tag
		var mine_y: bool = y.tag == GameState.player_tag
		return mine_x and not mine_y or (mine_x == mine_y and x.id < y.id))
	return list


## What the hover card says of armies seen only as an estimate: nation tag to the men they
## are guessed to number in the hovered province.
func card_guesses() -> Dictionary:
	var out := {}
	if _hover <= 0:
		return out
	for a: Army in Military.armies_at(GameState, _hover):
		if seen(a) == Intel.ESTIMATE:
			out[a.tag] = out.get(a.tag, 0.0) + Intel.estimate(a.men(), a.id)
	return out


## One line of the hover card for an army: name, general, men, morale and supply.
func card_line(a: Army) -> String:
	var line := "%s · %s men · morale %d%%" % [a.display_name, Fmt.people(a.men()), roundi(a.morale() * 100.0)]
	if not a.general_name.is_empty():
		line += " · " + a.general_name
	if not a.supplied:
		line += " · no supply"
	return line


## The rectangle being dragged (empty when no drag is going on).
func set_box(rect: Rect2) -> void:
	_box = rect
	queue_redraw()


## The front being drawn (province ids so far).
func set_draft(line: Array[int]) -> void:
	_draft = line
	_update_preview()
	queue_redraw()


func set_selected_front(id: int) -> void:
	_selected_front = id
	queue_redraw()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera and camera.zoom.x != _zoom:
		_zoom = camera.zoom.x
		queue_redraw()


## Works out the route the slowest selected army would take to the hovered province.
func _update_preview() -> void:
	_preview = []
	_preview_etas = []
	_preview_from = 0
	if _hover > 0 and _draft.is_empty() and not selected.is_empty():
		var slowest: Army = null
		for id in selected:
			var a: Army = GameState.armies.get(id)
			if a != null and (slowest == null or a.speed() < slowest.speed()):
				slowest = a
		if slowest != null and slowest.province != _hover:
			var route := Military.find_path(GameState, slowest.tag, slowest.speed(), slowest.province, _hover)
			if not route.is_empty():
				_preview = route
				_preview_from = slowest.province
				_preview_etas = Military.path_etas(GameState, slowest.tag, slowest.speed(), slowest.province, route,
						Military.move_days(GameState, slowest.tag, slowest.speed(), slowest.province, route[0]))
	queue_redraw()


func _draw() -> void:
	var px := 1.0 / maxf(_zoom, 0.05)
	_labels.clear()
	_draw_fronts(px)
	_draw_routes(px)
	_draw_preview(px)
	_draw_banners(px)
	_draw_expanded(px)
	_draw_card(px)
	_draw_battle_icons(px)
	for l in _labels:
		_front_label(l[0], l[1], l[2], px, l[3])
	_draw_draft(px)
	if _box.size != Vector2.ZERO:
		draw_rect(_box, Color(SELECT_COLOR, 0.12))
		draw_rect(_box, SELECT_COLOR, false, 1.5 * px)


# ------------------------------------------------------------------ banners

## How well the player sees this army (Intel.HIDDEN, ESTIMATE or EXACT): the "Armies on the map"
## setting can hide more of them, never show more than the player's eyes reach.
func seen(a: Army) -> int:
	if not UiSettings.shows_army(GameState, GameState.player_tag, a.tag):
		return Intel.HIDDEN
	return Intel.level(GameState, a)


## Whether the map draws anything for this army (exactly or as an estimate).
func shows(a: Army) -> bool:
	return seen(a) != Intel.HIDDEN


func _draw_banners(px: float) -> void:
	var by_province := {}
	for a: Army in GameState.armies.values():
		if not shows(a):
			continue
		if not by_province.has(a.province):
			by_province[a.province] = []
		by_province[a.province].append(a)
	var fanned := _expanded_armies().size() >= 2
	for id: int in by_province:
		var here: Array = by_province[id]
		if fanned and id == _expanded:
			# The armies seen exactly are drawn one by one below; estimates stay as banners.
			here = here.filter(func(a: Army) -> bool: return seen(a) == Intel.ESTIMATE)
			if here.is_empty():
				continue
		here.sort_custom(func(x: Army, y: Army) -> bool: return x.id < y.id)
		var centre: Vector2 = MapData.provinces[id].center
		var size := BANNER * px
		var gap := GAP * px
		# One banner per nation present, stacked around the centre.
		var tags: Array = []
		for a: Army in here:
			if not tags.has(a.tag):
				tags.append(a.tag)
		var top := centre.y - (size.y * tags.size() + gap * (tags.size() - 1)) * 0.5
		for i in tags.size():
			var tag: String = tags[i]
			var men := 0.0
			var picked := false
			var fighting := false
			var count := 0
			var biggest: Army = null
			var comp := {}
			var guess := false
			for a: Army in here:
				if a.tag != tag:
					continue
				# An army that is only estimated adds its estimate; what it is made of stays unknown.
				guess = seen(a) == Intel.ESTIMATE
				men += Intel.estimate(a.men(), a.id) if guess else a.men()
				count += 1
				picked = picked or selected.has(a.id)
				if selected.has(a.id):
					for type in a.composition():
						comp[type] = comp.get(type, 0) + a.composition()[type]
				fighting = fighting or a.fighting
				if biggest == null or a.men() > biggest.men():
					biggest = a
			var rect := Rect2(Vector2(centre.x - size.x * 0.5, top + i * (size.y + gap)), size)
			if guess:
				_draw_banner(rect, px, GameState.nations[tag].color, "unknown", men, 1, false, fighting, true)
			else:
				_draw_banner(rect, px, GameState.nations[tag].color, biggest.shown_icon(), men, count, picked, fighting)
			if not comp.is_empty():
				_draw_composition(comp, rect.get_center().x, rect.end.y + 3.0 * px, px)


## The armies standing in the expanded province: the player's first, then by id.
func _expanded_armies() -> Array[Army]:
	var list: Array[Army] = []
	if _expanded > 0:
		for a: Army in Military.armies_at(GameState, _expanded):
			if seen(a) == Intel.EXACT:
				list.append(a)
		list.sort_custom(func(x: Army, y: Army) -> bool:
			var mine_x: bool = x.tag == GameState.player_tag
			var mine_y: bool = y.tag == GameState.player_tag
			return mine_x and not mine_y or (mine_x == mine_y and x.id < y.id))
	return list


## Where each army of the expanded province is drawn: columns beside the province.
func _expanded_layout(px: float) -> Array:
	var list := _expanded_armies()
	var out := []
	if list.size() < 2:
		return out
	var centre: Vector2 = MapData.provinces[_expanded].center
	var size := BANNER * px
	var row_h := (BANNER.y + 36.0) * px
	var per_col := 8
	for i in list.size():
		var col := i / per_col
		var row := i % per_col
		var rows_here := mini(per_col, list.size() - col * per_col)
		var pos := Vector2(centre.x + (38.0 + col * (BANNER.x + 16.0)) * px, centre.y - rows_here * row_h * 0.5 + row * row_h)
		out.append({"army": list[i], "rect": Rect2(pos, size)})
	return out


func _draw_expanded(px: float) -> void:
	var layout := _expanded_layout(px)
	if layout.is_empty():
		return
	var centre: Vector2 = MapData.provinces[_expanded].center
	for entry in layout:
		var rect: Rect2 = entry.rect
		draw_line(centre, Vector2(rect.position.x, rect.get_center().y), Color(0, 0, 0, 0.55), 1.5 * px)
	draw_circle(centre, 5.0 * px, Color(0, 0, 0, 0.8))
	draw_circle(centre, 3.0 * px, Color.WHITE)
	for entry in layout:
		var a: Army = entry.army
		var rect: Rect2 = entry.rect
		_draw_banner(rect, px, GameState.nations[a.tag].color, a.shown_icon(), a.men(), 1, selected.has(a.id), a.fighting)
		var label := a.display_name if a.display_name.length() <= 24 else a.display_name.substr(0, 23) + "…"
		_pill(label, Vector2(rect.get_center().x, rect.end.y + 8.0 * px), px, Color(GameState.nations[a.tag].color.lightened(0.45), 1.0), 9)
		_draw_composition(a.composition(), rect.get_center().x, rect.end.y + 16.0 * px, px)


func _draw_banner(rect: Rect2, px: float, color: Color, icon: String, men: float, count: int, picked: bool, fighting: bool, guess := false) -> void:
	draw_rect(rect, Color(color, 0.8 if guess else 1.0))
	var frame := Rect2(rect.position + Vector2(2, 2) * px, Vector2(rect.size.y * 1.25 - 4.0 * px, rect.size.y - 4.0 * px))
	draw_rect(frame, Color(1, 1, 1, 0.92))
	_draw_symbol(frame, px, icon)
	var text_color := Color.WHITE if color.get_luminance() < 0.55 else Color.BLACK
	var label := ("~" if guess else "") + "%d" % roundi(men / 1000.0)
	if count > 1:
		label += " ×%d" % count
	var text_x := frame.end.x + 2.0 * px
	MapText.draw(self, _font, Vector2(text_x, rect.end.y - 6.0 * px), label, HORIZONTAL_ALIGNMENT_CENTER,
			rect.end.x - text_x - 1.0 * px, 11, text_color, px)
	var border := SELECT_COLOR if picked else (BATTLE_COLOR if fighting else Color(0, 0, 0, 0.85))
	draw_rect(rect, border, false, (2.5 if picked or fighting else 1.5) * px)
	var mark := _size_mark(men)
	if not mark.is_empty():
		MapText.draw(self, _font, Vector2(rect.position.x, rect.position.y - 2.0 * px), mark, HORIZONTAL_ALIGNMENT_CENTER,
				rect.size.x, 10, Color.BLACK, px)
	if fighting:
		MapText.draw(self, _font, Vector2(rect.end.x + 2.0 * px, rect.position.y + 12.0 * px), "⚔", HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 14, BATTLE_COLOR, px)


func _size_mark(men: float) -> String:
	for entry in Military.cfg.size_marks:
		if men >= entry[0]:
			return entry[1]
	return ""


## NATO-style unit symbol inside a frame.
func _draw_symbol(r: Rect2, px: float, icon: String) -> void:
	var ink := Color(0.05, 0.05, 0.08)
	var w := 1.8 * px
	var inner := r.grow(-2.0 * px)
	draw_rect(r, ink, false, 1.0 * px)
	match icon:
		"infantry":
			draw_line(r.position, r.end, ink, w)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), ink, w)
		"cavalry":
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), ink, w)
		"artillery":
			draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.3, ink)
		"guard":
			var pts := PackedVector2Array()
			var c := r.get_center()
			var rad := minf(r.size.x, r.size.y) * 0.46
			for i in 10:
				var ang := -PI / 2.0 + i * PI / 5.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * (rad if i % 2 == 0 else rad * 0.42))
			draw_colored_polygon(pts, ink)
		"fortress":
			draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.3), Vector2(inner.size.x, inner.size.y * 0.7)), ink)
			for i in 3:
				var cw := inner.size.x / 5.0
				draw_rect(Rect2(inner.position + Vector2(i * cw * 2.0, 0), Vector2(cw, inner.size.y * 0.3)), ink)
		"unknown":
			MapText.draw(self, _font, Vector2(r.position.x, r.end.y - 3.0 * px), "?", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ink, px)
		"reserve":
			draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), ink, w)
			draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), ink, w)


# ------------------------------------------------------------------ routes and fronts

## Lines from marching armies along their route. The selected armies show the days it takes
## to reach each province and the day they arrive; other marching armies of the player show
## their destination.
func _draw_routes(px: float) -> void:
	var mine := GameState.player_tag
	var row := 0
	for a: Army in GameState.armies.values():
		if a.path.is_empty() or a.tag != mine:
			continue
		var picked := selected.has(a.id)
		var etas := Military.army_etas(GameState, a)
		var from: Vector2 = MapData.provinces[a.province].center
		var color := SELECT_COLOR if picked else Color(1, 1, 1, 0.45)
		for i in a.path.size():
			var to: Vector2 = MapData.provinces[a.path[i]].center
			draw_line(from, to, color, (2.5 if picked else 1.5) * px)
			if picked and i < a.path.size() - 1:
				_pill("%dd" % roundi(etas[i]), to + Vector2(0, -(row * 14.0 + 12.0) * px), px, color, 10)
			from = to
		draw_circle(from, (5.0 if picked else 3.5) * px, color)
		_pill(_arrival(etas.back()), from + Vector2(0, -(row * 14.0 + 12.0) * px), px, color, 11 if picked else 10)
		if picked:
			row += 1


func _draw_preview(px: float) -> void:
	if _preview.is_empty():
		return
	var from: Vector2 = MapData.provinces[_preview_from].center
	for i in _preview.size():
		var to: Vector2 = MapData.provinces[_preview[i]].center
		draw_dashed_line(from, to, PREVIEW_COLOR, 2.0 * px, 6.0 * px)
		if i < _preview.size() - 1:
			_pill("%dd" % roundi(_preview_etas[i]), to + Vector2(0, 12.0 * px), px, PREVIEW_COLOR, 10)
		from = to
	_pill(_arrival(_preview_etas.back()), from + Vector2(0, 14.0 * px), px, PREVIEW_COLOR, 11)


func _arrival(days: float) -> String:
	var parts := Clock.date_after(roundi(days)).split(" ")
	return "%dd · %s %s" % [roundi(days), parts[0], parts[1].substr(0, 3)]


func _draw_fronts(px: float) -> void:
	var index := 0
	for f: Front in GameState.fronts.values():
		if f.tag != GameState.player_tag:
			continue
		var color: Color = FRONT_COLORS[index % FRONT_COLORS.size()]
		index += 1
		if f.provinces.is_empty():
			continue
		var chosen := f.id == _selected_front
		var stretches := _front_stretches(f)
		if stretches.is_empty():
			_draw_reserve_line(f, color, chosen, px)
		else:
			_draw_border_line(f, stretches, color, chosen, px)
		# Where each assigned army is meant to stand.
		if chosen:
			for id in f.army_ids:
				var a: Army = GameState.armies.get(id)
				var slot: int = f.slots.get(id, 0)
				if a != null and slot != 0 and a.province != slot:
					draw_dashed_line(MapData.provinces[a.province].center, MapData.provinces[slot].center, Color(color, 0.85), 1.6 * px, 5.0 * px)


## The stretches of border the front lies along: for every province of the line, the border with
## each neighbour held by a nation the front faces. Each is {line, enemy (the province across)}.
func _front_stretches(f: Front) -> Array:
	var out := []
	for p in f.provinces:
		for n: int in Military.neighbors(p):
			var holder: String = GameState.province_controller[n]
			var hostile := holder == f.against if not f.against.is_empty() else GameState.at_war(f.tag, holder)
			if not hostile or holder == f.tag:
				continue
			for line: PackedVector2Array in MapData.border_lines(p, n):
				out.append({"line": line, "enemy": n})
	return out


## The line itself, on the border, as on the war map of Hearts of Iron: a dark casing with the
## front's colour inside, and arrows across it pointing at the enemy.
func _draw_border_line(f: Front, stretches: Array, color: Color, chosen: bool, px: float) -> void:
	var casing := (9.0 if chosen else 7.0) * px
	var inner := (5.0 if chosen else 3.6) * px
	if chosen:
		for s in stretches:
			draw_polyline(s.line, Color(color, 0.28), 16.0 * px, true)
	for s in stretches:
		draw_polyline(s.line, Color(0.02, 0.03, 0.05, 0.92), casing, true)
	for s in stretches:
		draw_polyline(s.line, color, inner, true)
	var longest: PackedVector2Array = stretches[0].line
	for s in stretches:
		_draw_arrows(s.line, s.enemy, color, chosen, px)
		if _length(s.line) > _length(longest):
			longest = s.line
	_labels.append([f, _midpoint(longest), color, chosen])


## Arrows spaced along a stretch of border, each pointing at the province across it.
func _draw_arrows(line: PackedVector2Array, enemy: int, color: Color, chosen: bool, px: float) -> void:
	var length := _length(line)
	var screen := length / px
	var count := clampi(int(screen / 100.0), 0 if screen < 45.0 else 1, 5)
	if count == 0:
		return
	var target: Vector2 = MapData.provinces[enemy].center
	for i in count:
		var spot := _point_along(line, length * (i + 0.5) / count)
		var origin: Vector2 = spot.point
		var dir := _normal(line, spot.index, target - origin)
		var size := (19.0 if chosen else 16.0) * px
		var tail: Vector2 = origin - dir * size * 0.5
		var tip: Vector2 = origin + dir * size * 1.5
		var side := Vector2(-dir.y, dir.x)
		var head := PackedVector2Array([tail + dir * size * 0.55 + side * size * 0.75, tip, tail + dir * size * 0.55 - side * size * 0.75])
		draw_line(tail - dir * size * 0.55, tail + dir * size * 0.6, Color(0.02, 0.03, 0.05, 0.95), 7.5 * px, true)
		draw_line(tail - dir * size * 0.55, tail + dir * size * 0.6, color.lightened(0.15), 4.4 * px, true)
		draw_colored_polygon(head, color.lightened(0.15))
		draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), Color(0.02, 0.03, 0.05, 0.95), 1.8 * px, true)


## For a front with no enemy across it (a line drawn in friendly land): a dashed line through its
## provinces.
func _draw_reserve_line(f: Front, color: Color, chosen: bool, px: float) -> void:
	var line := PackedVector2Array()
	for p in f.provinces:
		line.append(MapData.provinces[p].center)
	if line.size() > 1:
		draw_polyline(line, Color(0.02, 0.03, 0.05, 0.6), (7.0 if chosen else 5.0) * px, true)
	for i in range(1, line.size()):
		draw_dashed_line(line[i - 1], line[i], color, (3.6 if chosen else 2.6) * px, 9.0 * px)
	for p in line:
		draw_circle(p, 4.0 * px, Color(0.02, 0.03, 0.05, 0.9))
		draw_circle(p, 2.6 * px, color)
	_labels.append([f, line[line.size() / 2], color, chosen])


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	return total


static func _midpoint(line: PackedVector2Array) -> Vector2:
	var spot := _point_along(line, _length(line) * 0.5)
	return spot.point


## The point a distance along a polyline, and the index of the segment it lies on.
static func _point_along(line: PackedVector2Array, distance: float) -> Dictionary:
	var left := distance
	for i in range(1, line.size()):
		var seg := line[i].distance_to(line[i - 1])
		if left <= seg or i == line.size() - 1:
			return {"point": line[i - 1].lerp(line[i], clampf(left / maxf(seg, 0.001), 0.0, 1.0)), "index": i}
		left -= seg
	return {"point": line[0], "index": 1}


## The unit normal of a segment, on the side the target lies.
static func _normal(line: PackedVector2Array, index: int, toward: Vector2) -> Vector2:
	var along: Vector2 = (line[index] - line[index - 1]).normalized()
	var n := Vector2(-along.y, along.x)
	return n if n.dot(toward) >= 0.0 else -n


## A chip on the line with the front's name, its armies and their men.
func _front_label(f: Front, at: Vector2, color: Color, px: float, chosen: bool) -> void:
	var men := 0.0
	for id in f.army_ids:
		var a: Army = GameState.armies.get(id)
		if a != null:
			men += a.men()
	var text := "%s · %d · %s" % [f.display_name, f.army_ids.size(), Fmt.people(men)]
	var fs := 12 if chosen else 11
	var w := MapText.size_of(_font, text, fs, px).x
	var pad := 4.0 * px
	var size := Vector2(w + pad * 2.0 + 5.0 * px, fs * px + pad * 1.6)
	var rect := Rect2(at - Vector2(size.x * 0.5, size.y + 14.0 * px), size)
	draw_rect(rect.grow(1.2 * px), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color(0.06, 0.08, 0.12, 0.94))
	draw_rect(Rect2(rect.position, Vector2(4.0 * px, rect.size.y)), color)
	MapText.draw(self, _font, rect.position + Vector2(pad + 4.0 * px, fs * px + pad * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color.WHITE, px)


func _draw_draft(px: float) -> void:
	if _draft.is_empty():
		return
	var line := PackedVector2Array()
	for p in _draft:
		line.append(MapData.provinces[p].center)
	if line.size() > 1:
		draw_polyline(line, Color(0.03, 0.04, 0.07, 0.8), 10.0 * px, true)
		draw_polyline(line, DRAFT_COLOR, 6.0 * px, true)
	for i in line.size():
		draw_circle(line[i], 8.0 * px, Color(0.03, 0.04, 0.07, 0.85))
		draw_circle(line[i], 6.0 * px, DRAFT_COLOR)
		_pill("%d" % (i + 1), line[i] + Vector2(0, -16.0 * px), px, DRAFT_COLOR, 10)


## The hover card: under the banners of the hovered province, a line and the unit symbols for
## each army standing there (at most CARD_ROWS, then a count of the rest).
func _draw_card(px: float) -> void:
	var list := card_armies()
	var guesses := card_guesses()
	if list.is_empty() and guesses.is_empty():
		return
	var centre: Vector2 = MapData.provinces[_hover].center
	var nations := {}
	for a in list:
		nations[a.tag] = true
	for tag: String in guesses:
		nations[tag] = true
	var y := centre.y + (BANNER.y * nations.size() * 0.5 + 12.0) * px
	for i in mini(list.size(), CARD_ROWS):
		var a := list[i]
		_pill(card_line(a), Vector2(centre.x, y), px, Color(GameState.nations[a.tag].color.lightened(0.45), 1.0), 9)
		_draw_composition(a.composition(), centre.x, y + 8.0 * px, px)
		y += 28.0 * px
	if list.size() > CARD_ROWS:
		_pill("+ %d more armies" % (list.size() - CARD_ROWS), Vector2(centre.x, y), px, Color.WHITE, 9)
		y += 14.0 * px
	var tags: Array = guesses.keys()
	tags.sort()
	for tag: String in tags:
		_pill("%s · %s men (estimate)" % [GameState.nations[tag].display_name, Intel.estimate_text(guesses[tag])], Vector2(centre.x, y), px,
				Color(GameState.nations[tag].color.lightened(0.45), 1.0), 9)
		y += 16.0 * px


## What an army is made of: a tiny symbol per unit type with how many of them, centred under
## a banner. `counts` maps unit type to number (see Army.composition).
func _draw_composition(counts: Dictionary, centre_x: float, top: float, px: float) -> void:
	var fs := 9
	var icon := Vector2(13.0, 10.0) * px
	var gap := 4.0 * px
	var widths := {}
	var total := 0.0
	for type in counts:
		var w: float = icon.x + 2.0 * px + MapText.size_of(_font, "%d" % counts[type], fs, px).x
		widths[type] = w
		total += w + gap
	total -= gap
	var pad := 3.0 * px
	draw_rect(Rect2(centre_x - total * 0.5 - pad, top - 1.0 * px, total + pad * 2.0, icon.y + 2.0 * px), Color(0.05, 0.07, 0.1, 0.85))
	var x := centre_x - total * 0.5
	for type in counts:
		var frame := Rect2(Vector2(x, top), icon)
		draw_rect(frame, Color(1, 1, 1, 0.92))
		_draw_symbol(frame, px * 0.6, type)
		MapText.draw(self, _font, Vector2(frame.end.x + 2.0 * px, top + icon.y - 1.0 * px), "%d" % counts[type],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color.WHITE, px)
		x += widths[type] + gap


## Small label on a dark pill, centred on a map position.
func _pill(text: String, at: Vector2, px: float, color: Color, font_px: int) -> void:
	var size := MapText.size_of(_font, text, font_px, px)
	var pad := 3.0 * px
	var rect := Rect2(at - Vector2(size.x * 0.5 + pad, size.y * 0.5 + pad * 0.5), size + Vector2(pad * 2.0, pad))
	draw_rect(rect, Color(0.05, 0.07, 0.1, 0.82))
	MapText.draw(self, _font, Vector2(rect.position.x + pad, rect.end.y - pad - size.y * 0.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px, Color(color, 1.0), px)
