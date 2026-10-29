class_name ArmyLayer
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
## Each army's colour on a front it shares (its stretch of the line, its label), by its place along the line: bright and
## far apart, so neighbours never look alike.
const ARMY_COLORS := [Color(0.35, 0.55, 1.0), Color(0.95, 0.3, 0.3), Color(0.35, 0.9, 0.4), Color(1.0, 0.85, 0.25),
		Color(0.3, 0.9, 0.95), Color(0.95, 0.45, 0.9), Color(1.0, 0.6, 0.2), Color(0.7, 0.55, 1.0)]
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
## The chips of front labels already drawn this frame, so the next one is moved clear of them.
var _label_rects: Array[Rect2] = []
## While true the banners are not drawn: each is listed in `markers` instead, for the 3D map to stand
## up as models ({province, tag, men, count, picked, fighting, guess, pos in map pixels}).
var markers_only := false:
	set(value):
		markers_only = value
		queue_redraw()
var markers: Array = []
var _collecting := false
## A layer that paints one banner card and nothing else (the 3D map puts the card above a model, as it is
## drawn on the flat map): it joins no group and follows no camera. `card` is a marker entry.
var card_only := false
var card := {}


func _ready() -> void:
	if card_only:
		_zoom = 1.0
		return
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


## The banners as markers (see `markers_only`), worked out now rather than at the next redraw.
func collect_markers() -> Array:
	markers.clear()
	_collecting = true
	var px := 1.0 / maxf(_zoom, 0.05)
	_draw_banners(px)
	for entry in _expanded_layout(px):
		var a: Army = entry.army
		markers.append({"province": a.province, "tag": a.tag, "men": a.men(), "count": 1, "picked": selected.has(a.id),
				"fighting": a.fighting, "guess": false, "pos": (entry.rect as Rect2).get_center(), "comp": a.composition(),
				"shown_comp": {}, "icon": a.shown_icon(), "heading": _heading_of(a, false), "expanded": true, "name": a.display_name, "army": a.id})
	_collecting = false
	return markers


## The size of a card (see `card_only`) and where its banner stands in it.
const CARD_SIZE := Vector2(170, 72)
const CARD_BANNER := Rect2(Vector2(54, 16), BANNER)


func set_card(entry: Dictionary) -> void:
	card = entry
	queue_redraw()


## Paints the card of one marker exactly as the flat map draws that banner.
func _paint_card() -> void:
	if card.is_empty():
		return
	var colour: Color = GameState.nations[card.tag].color
	_draw_banner(CARD_BANNER, 1.0, colour, card.get("icon", "auto"), card.men, card.count, card.picked, card.fighting, card.guess)
	var centre_x := CARD_BANNER.get_center().x
	if card.get("expanded", false):
		var name_text: String = card.name if card.name.length() <= 24 else card.name.substr(0, 23) + "…"
		_pill(name_text, Vector2(centre_x, CARD_BANNER.end.y + 8.0), 1.0, Color(colour.lightened(0.45), 1.0), 9)
		_draw_composition(card.comp, centre_x, CARD_BANNER.end.y + 16.0, 1.0)
	elif not card.get("shown_comp", {}).is_empty():
		_draw_composition(card.shown_comp, centre_x, CARD_BANNER.end.y + 3.0, 1.0)


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
	if card_only:
		return
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
	if card_only:
		_paint_card()
		return
	var px := 1.0 / maxf(_zoom, 0.05)
	_labels.clear()
	_label_rects.clear()
	markers.clear()
	_draw_fronts(px)
	_draw_offensives(px)
	_draw_routes(px)
	_draw_preview(px)
	_draw_banners(px)
	_draw_expanded(px)
	_draw_card(px)
	_draw_battle_icons(px)
	for l in _labels:
		if l.size() > 4:
			_sector_label(l[4], l[1], l[2], px, l[3])
		else:
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
	# The armies of the selected stacks: every stack of theirs is outlined in its army's colour.
	var chosen_roots := {}
	for id in selected:
		var picked_army: Army = GameState.armies.get(id)
		var root := FrontSolver.root_of(GameState, picked_army) if picked_army != null else null
		if root != null:
			chosen_roots[root.id] = true
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
			var make_up := {}
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
				if not guess:
					for type in a.composition():
						make_up[type] = make_up.get(type, 0) + a.composition()[type]
				fighting = fighting or a.fighting
				if biggest == null or a.men() > biggest.men():
					biggest = a
			var rect := Rect2(Vector2(centre.x - size.x * 0.5, top + i * (size.y + gap)), size)
			if not _collecting:
				# Labels keep clear of the banner; in 3D the card stands higher, above its model.
				_label_rects.append(rect.grow_individual(2.0 * px, (size.y * 2.0 if markers_only else 2.0 * px), 2.0 * px, 2.0 * px))
			if markers_only or _collecting:
				markers.append({"province": id, "tag": tag, "men": men, "count": 1 if guess else count, "picked": picked,
						"fighting": fighting, "guess": guess, "pos": rect.get_center(), "comp": make_up, "shown_comp": comp,
						"icon": "unknown" if guess else biggest.shown_icon(), "heading": _heading_of(biggest, guess)})
				continue
			if guess:
				_draw_banner(rect, px, GameState.nations[tag].color, "unknown", men, 1, false, fighting, true)
			else:
				_draw_banner(rect, px, GameState.nations[tag].color, biggest.shown_icon(), men, count, picked, fighting)
				# On a front shared out in sectors, a strip in the army's colour ties the stack to its stretch of the line.
				var army_colour: Variant = army_colour_of(biggest)
				if army_colour != null:
					draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 3.5 * px), Vector2(rect.size.x, 3.5 * px)), army_colour)
				if not picked and here.any(func(a: Army) -> bool: return a.tag == tag and chosen_roots.has(FrontSolver.root_of(GameState, a).id)):
					draw_rect(rect.grow(2.0 * px), Color(0.02, 0.03, 0.05, 0.9), false, 3.5 * px)
					draw_rect(rect.grow(2.0 * px), army_colour if army_colour != null else SELECT_COLOR, false, 2.0 * px)
				if tag == GameState.player_tag:
					_draw_status(rect, biggest, px)
			if not comp.is_empty():
				_draw_composition(comp, rect.get_center().x, rect.end.y + 3.0 * px, px)


## The marks on a stack's banner, at its top right: a green tick when its plan of attack is planned, a yellow triangle
## when it is out of supply, a red mark when its army is on no front in a war.
func _draw_status(rect: Rect2, a: Army, px: float) -> void:
	var at := rect.position + Vector2(rect.size.x + 2.0 * px, -2.0 * px)
	var dark := Color(0.02, 0.03, 0.05, 0.9)
	var root := FrontSolver.root_of(GameState, a)
	if not a.supplied:
		var tri := PackedVector2Array([at + Vector2(0, 9) * px, at + Vector2(5, 0) * px, at + Vector2(10, 9) * px])
		draw_colored_polygon(tri, Color(1.0, 0.82, 0.2))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), dark, 1.2 * px, true)
		at.x += 12.0 * px
	if root != null and Offensives.of_army(GameState, root) != null and a.planning >= float(Offensives.cfg().get("planning_ready", 0.5)):
		draw_polyline(PackedVector2Array([at + Vector2(0, 5) * px, at + Vector2(3.5, 9) * px, at + Vector2(10, 0) * px]), dark, 4.0 * px, true)
		draw_polyline(PackedVector2Array([at + Vector2(0, 5) * px, at + Vector2(3.5, 9) * px, at + Vector2(10, 0) * px]), Color(0.35, 0.95, 0.4), 2.2 * px, true)
		at.x += 12.0 * px
	if root != null and root.front_id == 0 and not GameState.wars_of(a.tag).is_empty() and Offensives.of_army(GameState, root) == null:
		draw_circle(at + Vector2(5, 5) * px, 5.0 * px, Color(0.9, 0.2, 0.18))
		MapText.draw(self, _font, at + Vector2(0, 9) * px, "!", HORIZONTAL_ALIGNMENT_CENTER, 10.0 * px, 9, Color.WHITE, px)


## The way an army is marching, as an angle on the map (radians, 0 east, turning toward south), or null if it stands.
func _heading_of(a: Army, guess: bool) -> Variant:
	if guess or a == null:
		return null
	var from: Vector2 = MapData.provinces[a.province].center
	if a.path.is_empty():
		# Standing: it faces the enemy next door, if there is one.
		for n: int in Military.neighbors(a.province):
			var holder: String = GameState.province_controller[n]
			if holder != a.tag and GameState.at_war(a.tag, holder):
				return (MapData.provinces[n].center - from).angle()
		return null
	var to: Vector2 = MapData.provinces[a.path[0]].center
	return (to - from).angle() if to != from else null


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
		# A stack going to its place on a front marches in its army's colour.
		var army_colour: Variant = army_colour_of(a)
		var color: Color = SELECT_COLOR if picked else (Color(army_colour, 0.85) if army_colour != null else Color(1, 1, 1, 0.45))
		var rail_ok := Military.railway_ok(GameState, a.tag)
		var train_at := Vector2.ZERO
		var longest := 0.0
		for i in a.path.size():
			var to: Vector2 = MapData.provinces[a.path[i]].center
			# By rail where a railway runs on its own ground: dashed, with a train on the longest run.
			var rail: bool = rail_ok and GameState.province_controller[a.path[i]] == a.tag and GameState.province_buildings[a.path[i]].get("railway", 0) > 0
			if rail:
				draw_line(from, to, Color(0.02, 0.03, 0.05, 0.6), (4.0 if picked else 3.0) * px)
				draw_dashed_line(from, to, color, (2.5 if picked else 1.8) * px, 5.0 * px)
				if from.distance_to(to) > longest:
					longest = from.distance_to(to)
					train_at = from.lerp(to, 0.5)
			else:
				draw_line(from, to, color, (2.5 if picked else 1.5) * px)
			if picked and i < a.path.size() - 1:
				_pill("%dd" % roundi(etas[i]), to + Vector2(0, -(row * 14.0 + 12.0) * px), px, color, 10)
			from = to
		if longest > 0.0:
			_draw_train(train_at, color, px)
		draw_circle(from, (5.0 if picked else 3.5) * px, color)
		if picked or army_colour == null:
			_pill(_arrival(etas.back()), from + Vector2(0, -(row * 14.0 + 12.0) * px), px, color, 11 if picked else 10)
		if picked:
			row += 1


## A small locomotive on a route, where it goes by rail.
func _draw_train(at: Vector2, color: Color, px: float) -> void:
	var body := Rect2(at + Vector2(-7, -6) * px, Vector2(14, 8) * px)
	draw_rect(body.grow(1.2 * px), Color(0.02, 0.03, 0.05, 0.9))
	draw_rect(body, color)
	draw_rect(Rect2(at + Vector2(2, -10) * px, Vector2(3, 4) * px), color)
	for x in [-4.0, 0.5, 4.5]:
		draw_circle(at + Vector2(x, 3.5) * px, 2.2 * px, Color(0.02, 0.03, 0.05, 0.95))
		draw_circle(at + Vector2(x, 3.5) * px, 1.2 * px, color)


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
		var stretches := _front_stretches(f) if f.kind != "garrison" else []
		if f.kind == "garrison":
			_draw_garrison(f, color, chosen, px)
		elif stretches.is_empty():
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
				out.append({"line": line, "enemy": n, "province": p})
	return out


# ------------------------------------------------------------------ plans of attack

## The player's plans of attack, as on a Hearts of Iron war map: a wide translucent arrow curving from the army to the
## middle of its target line (solid at the base, fading toward the point, its divisions and name along it), or for a
## spearhead a narrow bold arrow at its target with rings round it; the target line barbed in the army's colour, the
## lines of later phases dashed; and the ground the plan means to take striped (in the map's shader).
func _draw_offensives(px: float) -> void:
	var zone := {}
	for o: Offensive in GameState.offensives.values():
		if o.tag != GameState.player_tag or o.done:
			continue
		var root: Army = GameState.armies.get(o.army_id)
		if root == null:
			continue
		var colour: Color = army_colour_of(root) if army_colour_of(root) != null else GameState.nations[o.tag].color.lightened(0.3)
		var stacks := FrontSolver.stacks_of(GameState, root)
		var divisions := 0
		var source := Vector2.ZERO
		for st in stacks:
			divisions += st.units.size()
			source += MapData.provinces[st.province].center
		source /= maxf(stacks.size(), 1.0)
		var targets := o.targets()
		if targets.is_empty():
			continue
		var line := PackedVector2Array()
		for p in FrontSolver.order_line(targets):
			line.append(MapData.provinces[p].center)
		var aim: Vector2 = _midpoint(line) if line.size() > 1 else line[0]
		var text := "%d divisions · %s" % [divisions, root.display_name]
		if o.kind == "spearhead":
			_draw_arrow(source, aim, colour, 13.0 * px, 6.0 * px, 0.95, 0.85, text, px)
			for r in [14.0, 22.0]:
				draw_arc(aim, r * px, 0, TAU, 32, Color(0.02, 0.03, 0.05, 0.8), 4.5 * px, true)
				draw_arc(aim, r * px, 0, TAU, 32, colour, 2.4 * px, true)
		else:
			_draw_arrow(source, aim, colour, 30.0 * px, 14.0 * px, 0.7, 0.2, text, px)
			if line.size() > 1:
				var smooth := _smooth(line, 2)
				draw_polyline(smooth, Color(0.02, 0.03, 0.05, 0.8), 7.0 * px, true)
				var length := _length(smooth)
				var count := int(length / (10.0 * px))
				for i in count:
					var spot := _point_along(smooth, (i + 0.5) * length / maxf(count, 1))
					var n := _normal(smooth, spot.index, source - spot.point)
					var along := Vector2(n.y, -n.x)
					var at: Vector2 = spot.point
					draw_colored_polygon(PackedVector2Array([at + along * 3.0 * px, at + n * 7.5 * px, at - along * 3.0 * px]), colour)
				draw_polyline(smooth, colour, 4.2 * px, true)
		# The lines of the phases after this one, dashed.
		for k in range(o.phase + 1, o.phases.size()):
			var later := PackedVector2Array()
			var ids: Array[int] = []
			for p in o.phases[k]:
				ids.append(int(p))
			for p in FrontSolver.order_line(ids):
				later.append(MapData.provinces[p].center)
			for i in range(1, later.size()):
				draw_dashed_line(later[i - 1], later[i], Color(colour, 0.75), 2.6 * px, 8.0 * px)
		# The ground to take: enemy provinces inside the hull of the army and its targets.
		var hull_points := PackedVector2Array([source])
		for st in stacks:
			hull_points.append(MapData.provinces[st.province].center)
		for p in targets:
			hull_points.append(MapData.provinces[p].center)
		var hull := Geometry2D.convex_hull(hull_points)
		for p in targets:
			if GameState.province_controller[p] != o.tag:
				zone[p] = colour
		if hull.size() >= 3:
			for id in range(1, GameState.province_controller.size()):
				if GameState.province_controller[id] != o.tag and GameState.province_owner[id] != o.tag and Geometry2D.is_point_in_polygon(MapData.provinces[id].center, hull):
					zone[id] = colour
	get_tree().call_group("map_view", "set_plan_zone", zone)


## A curved arrow from `from` to `to` (a quadratic Bezier bending a little to one side), `wide` across at its base and
## `narrow` before its head, solid (`base_alpha`) at the base and fading to `tip_alpha`, with a label along its body.
func _draw_arrow(from: Vector2, to: Vector2, colour: Color, wide: float, narrow: float, base_alpha: float, tip_alpha: float, text: String, px: float) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var side := Vector2(-dir.y, dir.x)
	var head_len := minf(wide * 1.5, length * 0.35)
	var body_end := to - dir * head_len
	var control := (from + body_end) * 0.5 + side * length * 0.12
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colours_l := PackedColorArray()
	var colours_r := PackedColorArray()
	var steps := 24
	var last := from
	for i in steps + 1:
		var t := float(i) / steps
		var p := from.lerp(control, t).lerp(control.lerp(body_end, t), t)
		var tangent := (control - from).lerp(body_end - control, t).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var half := lerpf(wide, narrow, t) * 0.5
		left.append(p + normal * half)
		right.append(p - normal * half)
		var c := Color(colour, lerpf(base_alpha, tip_alpha, t))
		colours_l.append(c)
		colours_r.append(c)
		last = p
	var poly := left.duplicate()
	var cols := colours_l.duplicate()
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
		cols.append(colours_r[i])
	draw_polygon(poly, cols)
	var end_dir := (body_end - control).normalized()
	var end_side := Vector2(-end_dir.y, end_dir.x)
	var head := PackedVector2Array([last + end_side * wide * 0.8, to, last - end_side * wide * 0.8])
	draw_colored_polygon(head, Color(colour, maxf(tip_alpha, 0.35) + 0.15))
	draw_polyline(PackedVector2Array([head[0], head[1], head[2]]), Color(0.02, 0.03, 0.05, 0.6), 1.5 * px, true)
	# The label along the body, upright.
	var mid := from.lerp(control, 0.5).lerp(control.lerp(body_end, 0.5), 0.5)
	var angle := (body_end - from).angle()
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI
	var fs := 13
	var w := MapText.size_of(_font, text, fs, px).x
	draw_set_transform(mid, angle, Vector2(px, px))
	draw_string_outline(_font, Vector2(-w / px * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.02, 0.03, 0.05, 0.85))
	draw_string(_font, Vector2(-w / px * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The colour of a stack's army on the front it holds a sector of, or null (not on a front dealt in sectors).
static func army_colour_of(a: Army) -> Variant:
	var root := FrontSolver.root_of(GameState, a)
	if root == null or root.front_id == 0:
		return null
	var f: Front = GameState.fronts.get(root.front_id)
	if f == null or not f.spread or not f.sectors.has(root.id):
		return null
	return army_colors(f)[root.id]


## The army whose sector of a broad front a province of the line is in (0: none, the front is not dealt in sectors).
static func sector_owner(f: Front, province: int) -> int:
	if not f.spread or f.sectors.is_empty():
		return 0
	var i := f.order.find(province)
	if i < 0:
		return 0
	for id in f.sectors:
		var span: Vector2i = f.sectors[id]
		if i >= span.x and i < span.y:
			return id
	return 0


## The colour of each army on a front, by its place along the line (army id -> Color).
static func army_colors(f: Front) -> Dictionary:
	var spans: Array = []
	for id in f.sectors:
		spans.append([(f.sectors[id] as Vector2i).x, id])
	spans.sort()
	var out := {}
	for k in spans.size():
		# The colour the front keeps for the army (FrontSolver.keep_colours); by its place until it has one.
		out[spans[k][1]] = ARMY_COLORS[int(f.colours.get(spans[k][1], k)) % ARMY_COLORS.size()]
	return out


## The line itself, on the border, as on the war map of Hearts of Iron: a ribbon with a dark casing, in the front's
## colour or, on a broad front, each army's stretch in its own colour; barbs along it on the friendly side; a bracket
## where one army's stretch ends and the next begins; and a label for each army and for the front.
func _draw_border_line(f: Front, stretches: Array, color: Color, chosen: bool, px: float) -> void:
	var casing := (8.0 if chosen else 7.0) * px
	var inner := (5.0 if chosen else 4.2) * px
	var colours := army_colors(f)
	var lines: Array[PackedVector2Array] = []
	var tints: Array[Color] = []
	var owners: Array[int] = []
	for s in stretches:
		lines.append(_smooth(s.line, 2))
		var owner := sector_owner(f, s.province)
		owners.append(owner)
		tints.append(colours.get(owner, color))
	if chosen:
		for i in lines.size():
			draw_polyline(lines[i], Color(tints[i], 0.22), 14.0 * px, true)
	for l in lines:
		draw_polyline(l, Color(0.02, 0.03, 0.05, 0.8), casing, true)
	for i in lines.size():
		_draw_barbs(lines[i], stretches[i].enemy, tints[i], chosen, px)
	for i in lines.size():
		draw_polyline(lines[i], tints[i], inner, true)
	_draw_brackets(lines, owners, px)
	# A label for each army at the middle of its longest stretch; one for the front at its middle.
	var longest_of := {}
	var longest: PackedVector2Array = lines[0]
	for i in lines.size():
		if _length(lines[i]) > _length(longest):
			longest = lines[i]
		if owners[i] != 0 and (not longest_of.has(owners[i]) or _length(lines[i]) > _length(longest_of[owners[i]])):
			longest_of[owners[i]] = lines[i]
	for id: int in longest_of:
		_labels.append([f, _midpoint(longest_of[id]), colours[id], chosen, id])
	# The front's own chip; on a broad front, under the line, clear of the armies' chips.
	_labels.append([f, _midpoint(longest) + (Vector2(0, 40.0 * px) if longest_of.size() > 1 else Vector2.ZERO), color, chosen])


## Barbs: small teeth along the line every few screen pixels, on the friendly side (away from the province across),
## as on the war map of Hearts of Iron.
func _draw_barbs(line: PackedVector2Array, enemy: int, color: Color, chosen: bool, px: float) -> void:
	var length := _length(line)
	var step := 10.0 * px
	var count := int(length / step)
	if count < 1:
		return
	var away: Vector2 = MapData.provinces[enemy].center
	var size := (7.5 if chosen else 6.5) * px
	var dark := Color(0.02, 0.03, 0.05, 0.85)
	for i in count:
		var spot := _point_along(line, (i + 0.5) * length / count)
		var at: Vector2 = spot.point
		var n := -_normal(line, spot.index, away - at)
		var along := Vector2(n.y, -n.x)
		var tooth := PackedVector2Array([at + along * size * 0.45, at + n * size * 1.25 + along * size * 0.1, at + n * size * 1.25 - along * size * 0.1, at - along * size * 0.45])
		draw_colored_polygon(tooth, color.lightened(0.1))
		draw_polyline(PackedVector2Array([tooth[0], tooth[1], tooth[2], tooth[3]]), dark, 1.2 * px, true)


## A bracket where one army's stretch of a broad front meets the next: a short white bar across the line, cased.
func _draw_brackets(lines: Array[PackedVector2Array], owners: Array[int], px: float) -> void:
	var ends := []
	for i in lines.size():
		if owners[i] == 0 or lines[i].size() < 2:
			continue
		ends.append([lines[i][0], lines[i][1], owners[i]])
		ends.append([lines[i][lines[i].size() - 1], lines[i][lines[i].size() - 2], owners[i]])
	var done: Array[Vector2] = []
	for a in ends:
		for b in ends:
			if a[2] == b[2] or (a[0] as Vector2).distance_to(b[0]) > 3.0 * px:
				continue
			var at: Vector2 = a[0]
			if done.any(func(d: Vector2) -> bool: return d.distance_to(at) < 6.0 * px):
				continue
			done.append(at)
			var along: Vector2 = ((a[0] as Vector2) - (a[1] as Vector2)).normalized()
			var across := Vector2(-along.y, along.x) * 9.0 * px
			draw_line(at - across, at + across, Color(0.02, 0.03, 0.05, 0.9), 5.0 * px, true)
			draw_line(at - across, at + across, Color(0.97, 0.97, 0.92), 2.4 * px, true)
			for e: Vector2 in [at - across, at + across]:
				draw_line(e, e + along * 4.0 * px, Color(0.97, 0.97, 0.92), 2.0 * px, true)
				draw_line(e, e - along * 4.0 * px, Color(0.97, 0.97, 0.92), 2.0 * px, true)


## A chip on an army's stretch of a broad front: its divisions and name, in its colour.
func _sector_label(army_id: int, at: Vector2, color: Color, px: float, chosen: bool) -> void:
	var root: Army = GameState.armies.get(army_id)
	if root == null:
		return
	var divisions := 0
	for s: Army in FrontSolver.stacks_of(GameState, root):
		divisions += s.units.size()
	var text := "%d divisions · %s" % [divisions, root.display_name]
	var fs := 11 if chosen else 10
	var w := MapText.size_of(_font, text, fs, px).x
	var pad := 3.5 * px
	var size := Vector2(w + pad * 2.0 + 5.0 * px, fs * px + pad * 1.6)
	var rect := _clear_of_labels(Rect2(at - Vector2(size.x * 0.5, size.y + 12.0 * px), size), px)
	draw_rect(rect.grow(1.2 * px), Color(0, 0, 0, 0.55))
	draw_rect(rect, Color(0.06, 0.08, 0.12, 0.9))
	draw_rect(Rect2(rect.position, Vector2(4.0 * px, rect.size.y)), color)
	MapText.draw(self, _font, rect.position + Vector2(pad + 4.0 * px, fs * px + pad * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, color.lightened(0.45), px)


## Corner-cutting: each pass replaces every corner by two points a quarter along its sides, so the
## zigzag of province edges becomes a gentle curve (the ends stay put).
static func _smooth(line: PackedVector2Array, passes: int) -> PackedVector2Array:
	var out := line
	for _p in passes:
		if out.size() < 3:
			break
		var next := PackedVector2Array([out[0]])
		for i in range(1, out.size() - 1):
			next.append(out[i - 1].lerp(out[i], 0.75) if i > 1 else out[i - 1].lerp(out[i], 0.5))
			next.append(out[i].lerp(out[i + 1], 0.25))
		next.append(out[out.size() - 1])
		out = next
	return out


## A garrison: a shield ring on each province it guards, in the colour of the army holding it (or the front's).
func _draw_garrison(f: Front, color: Color, chosen: bool, px: float) -> void:
	var colours := army_colors(f)
	for p in f.provinces:
		var c: Vector2 = MapData.provinces[p].center + Vector2(0, -22.0 * px)
		var tint: Color = colours.get(sector_owner(f, p), color)
		var r := (8.0 if chosen else 7.0) * px
		var shield := PackedVector2Array([c + Vector2(-r, -r * 0.8), c + Vector2(r, -r * 0.8), c + Vector2(r, r * 0.1), c + Vector2(0, r * 1.1), c + Vector2(-r, r * 0.1)])
		draw_colored_polygon(shield, Color(0.06, 0.08, 0.12, 0.9))
		draw_polyline(PackedVector2Array(Array(shield) + [shield[0]]), tint, 2.2 * px, true)
		draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.6), tint, 1.6 * px, true)
	if not f.provinces.is_empty():
		_labels.append([f, MapData.provinces[f.provinces[0]].center + Vector2(0, -34.0 * px), color, chosen])


## For a front with no enemy across it (a line drawn in friendly land, a fallback line): a striped, dashed line through
## its provinces, with short stripes across it.
func _draw_reserve_line(f: Front, color: Color, chosen: bool, px: float) -> void:
	var line := PackedVector2Array()
	for p in f.provinces:
		line.append(MapData.provinces[p].center)
	if line.size() > 1:
		draw_polyline(line, Color(0.02, 0.03, 0.05, 0.6), (8.0 if chosen else 6.5) * px, true)
	for i in range(1, line.size()):
		draw_dashed_line(line[i - 1], line[i], color, (4.0 if chosen else 3.2) * px, 9.0 * px)
		var seg := line[i] - line[i - 1]
		var across := Vector2(-seg.y, seg.x).normalized() * 5.0 * px
		var stripes := int(seg.length() / (14.0 * px))
		for k in stripes:
			var at := line[i - 1].lerp(line[i], (k + 0.5) / maxf(stripes, 1))
			draw_line(at - across, at + across, Color(color, 0.8), 1.6 * px, true)
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


## A label's chip moved up, a step at a time, until it no longer covers one drawn before it; then kept.
func _clear_of_labels(rect: Rect2, px: float) -> Rect2:
	for _i in 8:
		var hit := false
		for r in _label_rects:
			if r.grow(1.5 * px).intersects(rect):
				hit = true
				rect.position.y = r.position.y - rect.size.y - 3.0 * px
				break
		if not hit:
			break
	_label_rects.append(rect)
	return rect


## A chip on the line with the front's name, its armies, their divisions and men.
func _front_label(f: Front, at: Vector2, color: Color, px: float, chosen: bool) -> void:
	var men := 0.0
	var divisions := 0
	for id in f.army_ids:
		var root: Army = GameState.armies.get(id)
		if root == null:
			continue
		for a: Army in FrontSolver.stacks_of(GameState, root):
			men += a.men()
			divisions += a.units.size()
	var text := "%s · %d divisions · %s" % [f.display_name, divisions, Fmt.people(men)] if divisions > 0 else "%s · no armies" % f.display_name
	var fs := 12 if chosen else 11
	var w := MapText.size_of(_font, text, fs, px).x
	var pad := 4.0 * px
	var size := Vector2(w + pad * 2.0 + 5.0 * px, fs * px + pad * 1.6)
	var rect := _clear_of_labels(Rect2(at - Vector2(size.x * 0.5, size.y + 14.0 * px), size), px)
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
