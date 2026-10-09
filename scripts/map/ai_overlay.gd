extends Node2D
## A tuning aid (toggle with F9): draws what the AI is up to. For every nation but the player's,
## a line from each army to the end of its order, the campaign target of each offence (a ring)
## with the staging province it gathers in, and the provinces of each front. Not part of the
## game proper; it shows nothing unless switched on.

const ORDER_COLOR := Color(1.0, 0.9, 0.3, 0.9)
const TARGET_COLOR := Color(1.0, 0.25, 0.2, 0.95)
const STAGING_COLOR := Color(0.3, 0.9, 1.0, 0.9)
const FRONT_COLOR := Color(0.6, 1.0, 0.5, 0.45)

var shown := false


func _ready() -> void:
	z_index = 6
	visible = false
	GameState.armies_changed.connect(_refresh)
	GameState.fronts_changed.connect(_refresh)
	GameState.scenario_loaded.connect(_refresh)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		shown = not shown
		visible = shown
		queue_redraw()


func _refresh() -> void:
	if shown:
		queue_redraw()


## What the overlay shows, as plain data: {kind: "order" | "target" | "staging" | "front",
## tag, from, to} with `from` and `to` province ids (equal for a ring).
static func marks(gs: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Army in gs.armies.values():
		if a.tag == gs.player_tag or a.path.is_empty():
			continue
		out.append({"kind": "order", "tag": a.tag, "from": a.province, "to": a.path[a.path.size() - 1]})
	var tags: Array = gs.ai_campaign.keys()
	tags.sort()
	for tag: String in tags:
		var c: Dictionary = gs.ai_campaign[tag]
		out.append({"kind": "target", "tag": tag, "from": c.target, "to": c.target})
		out.append({"kind": "staging", "tag": tag, "from": c.staging, "to": c.target})
	for f: Front in gs.fronts.values():
		if f.tag == gs.player_tag:
			continue
		for p in f.provinces:
			out.append({"kind": "front", "tag": f.tag, "from": p, "to": p})
	return out


func _draw() -> void:
	var px := 1.0 / maxf(get_viewport().get_canvas_transform().get_scale().x, 0.05)
	for m in marks(GameState):
		var a: Vector2 = MapData.provinces[m.from].center
		var b: Vector2 = MapData.provinces[m.to].center
		match m.kind:
			"order":
				draw_line(a, b, ORDER_COLOR, 2.0 * px)
			"target":
				draw_arc(a, 14.0 * px, 0.0, TAU, 24, TARGET_COLOR, 3.0 * px)
			"staging":
				draw_arc(a, 10.0 * px, 0.0, TAU, 24, STAGING_COLOR, 2.0 * px)
				draw_line(a, b, STAGING_COLOR, 1.5 * px)
			"front":
				draw_circle(a, 5.0 * px, FRONT_COLOR)
