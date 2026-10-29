class_name BattlePlanToolbar
extends PanelContainer
## The Battle Plans toolbar over the command panel's cards, as in Hearts of Iron. It acts on the selected armies (a
## general's card, or a field marshal's for the whole group) and holds one tool at a time; while a tool is in hand the
## map's clicks and drags come here (MapView routes them through the "map_tool" group) instead of selecting and moving,
## the pointer is a crosshair and a hint follows it. Every order still goes through a command. Halt and Advance are on
## the cards (CommandCard).
##
##   - Train: puts the armies on exercise, or takes them off (SetTraining).
##   - Careful / Balanced / Aggressive: one button that goes round the three; how readily the plans attack.
##   - Create/Edit front line: click a border to put the armies on the stretch of it there, Shift+click for the whole
##     border; on the army's own drawn line, drag from its end to lengthen it or over its ends to shorten it.
##   - Attack line: drag across enemy ground to mark the line to push to (Shift: as the next phase; Ctrl: added to the
##     line it has; starting on its line takes provinces off).
##   - Spearhead: click the one province to break through at.
##   - Fallback line: drag a line through your own ground, behind the front, to dig in on.
##   - Edit order (the pencil): drag over the army's target line or drawn line to add provinces or take them off; a
##     spearhead's or a landing's target moves to the province clicked.
##   - Add to front line: click a front on the map to put the armies on it.
##   - Remove from front line: takes the armies off their fronts and drops their plans.
##   - Delete: click an order on the map to remove it; right click the button to clear every order of the selection
##     (or all of yours with nothing selected).
##   - "+" at the right opens a second row: Execute, Garrison, Naval invasion, Naval support, Paradrop (off: no aircraft
##     yet), and the command panel's Merge, Split, Halt and Fleets (add_extra).
## Esc puts the tool down.

signal tool_changed(tool: String)

## Each tool: its icon, its name and what it does (the tooltip), and the hint that follows the pointer.
const TOOLS := {
	"front": {"icon": "frontline", "name": "Create/Edit front line",
		"tip": "Click a border to put the selected armies on the stretch of it there; Shift+click for the whole border with that nation. They spread along it and hold it. On a line of their own you drew, drag on from its end to lengthen it, or over its end to shorten it.",
		"hint": "Click a border · Shift+click: the whole border"},
	"offensive": {"icon": "offensive", "name": "Attack line",
		"tip": "Drag across enemy ground to mark the line to push to. Needs the army on a front. Shift: add it as the next phase. Ctrl: add the provinces to the line it has. Starting on its line takes provinces off.",
		"hint": "Drag across enemy ground · Shift: next phase · Ctrl: add"},
	"spearhead": {"icon": "spearhead", "name": "Spearhead",
		"tip": "Click one enemy province: the army gathers and breaks through there with its whole weight. Needs the army on a front.",
		"hint": "Click the province to break through at"},
	"fallback": {"icon": "fallback", "name": "Fallback line",
		"tip": "Drag a line through your own ground, behind the front: the armies go there and dig in deeper and faster than on the border.",
		"hint": "Drag a line through your own ground"},
	"edit": {"icon": "edit", "name": "Edit order",
		"tip": "Drag over the selected army's target line, or its drawn front line, to add provinces or take them off (a click on one takes it off). A spearhead's or a landing's target moves to the province clicked.",
		"hint": "Drag over provinces to add or take them off"},
	"garrison": {"icon": "garrison", "name": "Garrison",
		"tip": "Guard ports, forts, cities and the capital: tick what to guard, then click your provinces. Enter or Finish when done.",
		"hint": "Click your provinces · Enter to finish"},
	"invasion": {"icon": "invasion", "name": "Naval invasion",
		"tip": "Click the port to sail from, then the coast to land on. The army gathers in the port and sails once transports there have room for it.",
		"hint": "Click the port to sail from"},
	"support": {"icon": "naval_support", "name": "Naval support",
		"tip": "Click a coast: the nearest free warships sail off it on Shore support, adding to your armies' attacks there.",
		"hint": "Click the coast to support"},
	"add": {"icon": "add_front", "name": "Add to front line",
		"tip": "Click one of your fronts on the map: the selected armies join it and spread along it with the armies already there.",
		"hint": "Click a front to put the armies on it"},
	"delete": {"icon": "delete", "name": "Delete order/front line",
		"tip": "Click an order on the map to remove it and release its armies. Right click this button to clear every order of the selected armies (all of yours with none selected).",
		"hint": "Click an order to delete it"},
}
const AGGRESSIVENESS := [
	["careful", "chevron1", "Careful: attacks only at odds of two to one and halts when morale falls under 60%."],
	["balanced", "chevron2", "Balanced: attacks at fair odds and halts at the usual morale."],
	["aggressive", "chevron3", "Aggressive: attacks at even odds, at once, whatever the morale and the losses."],
]
const ICON := 18
## What a garrison can be set to guard, with what makes a province one of them.
const GARRISON_KINDS := [["port", "Ports"], ["fort", "Forts"], ["city", "Cities"], ["capital", "The capital"]]
## How far from a clicked province a garrison looks for what is ticked (provinces).
const AREA_HOPS := 2

var tool := ""
## Set by the command panel: no title line; what the selection is doing goes in the tooltip instead.
var compact := false:
	set(value):
		compact = value
		_head.visible = not compact
var _head := HBoxContainer.new()
## The aggressiveness new plans get (and the selected plans have).
var aggressiveness := "balanced"
var _armies: Array[Army] = []
var _stroke: Array[int] = []
var _drawing := false
## What the drag reshapes: "" (a new line), "plan" (the selected army's target line) or "front" (its drawn line).
var _editing := ""
## An edit drag: the province it started on, and whether it adds or takes off ("" until it moves; a click without a
## drag takes off the province clicked).
var _press := 0
var _edit_mode := ""
var _buttons := {}
var _train := Button.new()
var _aggr := Button.new()
var _remove := Button.new()
var _status := Label.new()
var _hint := Label.new()
## The second row the "+" button opens, and what is in it of the toolbar's own.
var _extend := Button.new()
var _extra := HBoxContainer.new()
var _execute := Button.new()
var _paradrop := Button.new()
## Naval invasion: the port chosen first.
var _port := 0
var _garrison_box := PanelContainer.new()
var _garrison_checks := {}


func _ready() -> void:
	add_to_group("map_tool")
	add_to_group("battle_plan_toolbar")
	add_theme_stylebox_override("panel", UiTheme.frame())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var head := _head
	head.visible = not compact
	var title := Label.new()
	title.text = "Battle Plans"
	title.modulate = UiTheme.GOLD.lightened(0.2)
	head.add_child(title)
	_status.modulate = Fmt.DIM
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(120, 0)
	head.add_child(_status)
	box.add_child(head)
	# The second row, over the first so the first stays put: the tools the "+" button opens.
	_extra.add_theme_constant_override("separation", 2)
	_extra.visible = false
	box.add_child(_extra)
	_execute = _icon_button("play", "Execute: launch the selected armies' plans (they attack once planned, at once if aggressive), or halt them to plan again. The cards' green arrows do the same, army by army.")
	_execute.toggle_mode = true
	_execute.pressed.connect(_on_execute)
	_extra.add_child(_execute)
	_extra.add_child(VSeparator.new())
	for key in ["garrison", "invasion", "support"]:
		_extra.add_child(_tool_button(key))
	_paradrop = _icon_button("paradrop", "Paradrop: there are no aircraft or airborne troops in this age.")
	_paradrop.disabled = true
	_extra.add_child(_paradrop)
	_extra.add_child(VSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	_train = _icon_button("train", "Train: put the selected armies on exercise. Standing still, their divisions gain experience (up to a fifth more power over four months); their men cost half again as much upkeep meanwhile. Press again to stop.")
	_train.toggle_mode = true
	_train.pressed.connect(_on_train)
	row.add_child(_train)
	_aggr = _icon_button("chevron2", "")
	_aggr.pressed.connect(_on_aggressiveness)
	row.add_child(_aggr)
	row.add_child(VSeparator.new())
	for key in ["front", "offensive", "spearhead", "fallback", "edit"]:
		row.add_child(_tool_button(key))
	row.add_child(VSeparator.new())
	row.add_child(_tool_button("add"))
	_remove = _icon_button("remove_front", "Remove from front line: take the selected armies off their fronts and drop their plans.")
	_remove.pressed.connect(_on_unassign)
	row.add_child(_remove)
	row.add_child(VSeparator.new())
	var delete := _tool_button("delete")
	delete.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			clear_all_orders())
	row.add_child(delete)
	row.add_child(VSeparator.new())
	_extend = _icon_button("plus", "More: Execute, Garrison, Naval invasion, Naval support, Paradrop, Merge, Split, Halt and Fleets, in a row over these.")
	_extend.toggle_mode = true
	_extend.toggled.connect(func(on: bool) -> void: _extra.visible = on)
	row.add_child(_extend)
	# The hint that follows the pointer while a tool is in hand.
	_hint.top_level = true
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.z_index = 50
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.04, 0.05, 0.07, 0.9)
	hint_style.border_color = UiTheme.GOLD
	hint_style.set_border_width_all(1)
	hint_style.set_content_margin_all(4)
	_hint.add_theme_stylebox_override("normal", hint_style)
	_hint.add_theme_font_size_override("font_size", 13)
	add_child(_hint)
	_build_garrison_box()
	GameState.fronts_changed.connect(_refresh)
	GameState.armies_changed.connect(_refresh)
	_refresh()


func _icon_button(icon: String, tip: String) -> Button:
	var b := Button.new()
	b.icon = Icons.get_icon(icon, ICON)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 26)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## Puts one of the command panel's buttons (Merge, Split, Halt, Fleets) in the row "+" opens.
func add_extra(control: Control) -> void:
	_extra.add_child(control)


func _tool_button(key: String) -> Button:
	var info: Dictionary = TOOLS[key]
	var b := _icon_button(info.icon, "%s: %s" % [info.name, info.tip])
	b.toggle_mode = true
	b.pressed.connect(set_tool.bind(key))
	_buttons[key] = b
	return b


## The checklist of a garrison: what to guard, and Finish / Cancel. It stands above the toolbar while the tool is in hand.
func _build_garrison_box() -> void:
	_garrison_box.top_level = true
	_garrison_box.visible = false
	_garrison_box.add_theme_stylebox_override("panel", UiTheme.frame())
	var box := VBoxContainer.new()
	_garrison_box.add_child(box)
	var title := Label.new()
	title.text = "Garrison: what to guard"
	title.modulate = UiTheme.GOLD.lightened(0.2)
	box.add_child(title)
	for kind: Array in GARRISON_KINDS:
		var check := CheckBox.new()
		check.text = kind[1]
		check.focus_mode = Control.FOCUS_NONE
		check.button_pressed = kind[0] != "capital"
		_garrison_checks[kind[0]] = check
		box.add_child(check)
	var tip := Label.new()
	tip.text = "Click a province of yours: the ticked kinds\nwithin %d provinces of it are added (with\nnothing ticked, the province itself)." % AREA_HOPS
	tip.modulate = Fmt.DIM
	box.add_child(tip)
	var buttons := HBoxContainer.new()
	var finish := Button.new()
	finish.text = "Finish"
	finish.focus_mode = Control.FOCUS_NONE
	finish.pressed.connect(finish_garrison)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(set_tool.bind(""))
	buttons.add_child(finish)
	buttons.add_child(cancel)
	box.add_child(buttons)
	add_child(_garrison_box)


# ------------------------------------------------------------------ state

## The command panel's selection.
func set_armies(armies: Array[Army]) -> void:
	_armies = armies
	_refresh()


func is_active() -> bool:
	return tool != ""


## The armies (not detachments) of the selected stacks, on land.
func roots() -> Array[Army]:
	var out: Array[Army] = []
	for a in _armies:
		var root := FrontSolver.root_of(GameState, a)
		if root != null and not out.has(root) and not root.embarked():
			out.append(root)
	return out


func _plans() -> Array[Offensive]:
	var out: Array[Offensive] = []
	for root in roots():
		var o := Offensives.of_army(GameState, root)
		if o != null:
			out.append(o)
	return out


## Takes up a tool ("" puts it down; taking up the one in hand puts it down too).
func set_tool(key: String) -> void:
	if key == tool:
		key = ""
	var why := tool_problem(key)
	if not why.is_empty():
		_say(why)
		key = ""
	_end_stroke()
	tool = key
	_port = 0
	for k: String in _buttons:
		_buttons[k].set_pressed_no_signal(k == tool)
	_garrison_box.visible = tool == "garrison"
	if _garrison_box.visible:
		_place_garrison_box.call_deferred()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if tool != "" else Input.CURSOR_ARROW)
	_hint.visible = tool != ""
	_update_hint()
	tool_changed.emit(tool)


## Why a tool cannot be taken up now, or "".
func tool_problem(key: String) -> String:
	if key in ["offensive", "spearhead", "add", "edit", "invasion"] and roots().is_empty():
		return "Select an army first."
	if key in ["offensive", "spearhead"] and not roots().any(func(r: Army) -> bool: return r.front_id != 0):
		return "Put the army on a front first (Create/Edit front line)."
	if key == "support" and _warship_fleets().is_empty():
		return "You have no warships free to support an attack."
	return ""


func _refresh() -> void:
	if not is_inside_tree():
		return
	var rs := roots()
	var plans := _plans()
	if not plans.is_empty():
		aggressiveness = plans[0].aggressiveness
	var index := maxi(0, AGGRESSIVENESS.map(func(a: Array) -> String: return a[0]).find(aggressiveness))
	_aggr.icon = Icons.get_icon(AGGRESSIVENESS[index][1], ICON)
	_aggr.tooltip_text = "%s\nClick for %s." % [AGGRESSIVENESS[index][2], AGGRESSIVENESS[(index + 1) % AGGRESSIVENESS.size()][0].capitalize()]
	_train.disabled = rs.is_empty()
	_train.set_pressed_no_signal(not rs.is_empty() and rs.all(func(r: Army) -> bool: return r.training))
	_remove.disabled = not rs.any(func(r: Army) -> bool: return r.front_id != 0 or Offensives.of_army(GameState, r) != null)
	var running := not plans.is_empty() and plans.all(func(o: Offensive) -> bool: return o.active)
	_execute.disabled = plans.is_empty()
	_execute.set_pressed_no_signal(running)
	_execute.icon = Icons.get_icon("pause" if running else "play", ICON)
	for key in ["offensive", "spearhead", "add", "edit", "invasion"]:
		_buttons[key].disabled = rs.is_empty() and tool != key
	_status.text = _status_text(plans)
	tooltip_text = "Battle Plans · " + _status.text


func _status_text(plans: Array[Offensive]) -> String:
	var rs := roots()
	if rs.is_empty():
		return "Select an army to give it orders"
	var who: String = rs[0].display_name if rs.size() == 1 else "%d armies" % rs.size()
	var drill := " · on exercise" if rs.all(func(r: Army) -> bool: return r.training) else ""
	if plans.is_empty():
		return "%s · no plan%s" % [who, drill]
	var o := plans[0]
	var what: String = {"broad": "push", "spearhead": "spearhead", "invasion": "landing"}.get(o.kind, o.kind)
	var state := "advancing" if o.active else "planning %d%%" % roundi(Offensives.planning_of(GameState, rs[0]) * 100.0)
	var phase := ", phase %d/%d" % [o.phase + 1, o.phases.size()] if o.phases.size() > 1 else ""
	return "%s · %s%s · %s%s" % [who, what, phase, state, drill]


func _update_hint() -> void:
	if tool == "":
		return
	var text: String = TOOLS[tool].hint
	if tool == "invasion" and _port != 0:
		text = "Sailing from %s: click the coast to land on" % MapData.provinces[_port].name
	_hint.text = "%s: %s · Esc to stop" % [TOOLS[tool].name, text]
	_hint.reset_size()


func _process(_delta: float) -> void:
	if _hint.visible:
		_hint.position = get_viewport().get_mouse_position() + Vector2(18, 20)


func _place_garrison_box() -> void:
	_garrison_box.reset_size()
	var at := get_global_rect().position
	_garrison_box.position = Vector2(at.x + size.x - _garrison_box.size.x, at.y - _garrison_box.size.y - 4.0)


## Esc puts the tool down before anything else takes the key; Enter finishes a garrison.
func _input(event: InputEvent) -> void:
	if tool == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		set_tool("")
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and tool == "garrison":
		finish_garrison()
		get_viewport().set_input_as_handled()


func _say(text: String) -> void:
	get_tree().call_group("event_feed", "say", text, Fmt.WARN)


# ------------------------------------------------------------------ the map's clicks (MapView)

func map_press(province: int, zone: int, _button: int, shift: bool) -> void:
	match tool:
		"front":
			var f := _drawn_front()
			if f != null and _touches_line(f, province):
				_begin_edit("front", f.provinces, province)
			else:
				_front_at(province, shift)
		"offensive":
			var o := _broad_plan()
			if o != null and o.targets().has(province):
				_begin_edit("plan", o.targets(), province)
			elif o != null and Input.is_key_pressed(KEY_CTRL):
				_begin_edit("plan", o.targets(), province)
			else:
				_drawing = true
				_editing = ""
				_stroke.clear()
				_add_to_stroke(province)
		"fallback":
			_drawing = true
			_editing = ""
			_stroke.clear()
			_add_to_stroke(province)
		"spearhead":
			_spearhead_at(province)
		"edit":
			_edit_at(province)
		"garrison":
			_garrison_at(province)
		"invasion":
			_invasion_at(province)
		"support":
			_support_at(province, zone)
		"add":
			_add_at(province)
		"delete":
			_delete_at(province)


func map_drag(province: int) -> void:
	if not _drawing or province < 1:
		return
	if _editing != "":
		_edit_touch(province)
	else:
		_add_to_stroke(province)


func map_release(_province: int, _button: int) -> void:
	if not _drawing:
		return
	_drawing = false
	if _editing != "":
		_edit_finish()
		return
	match tool:
		"offensive":
			_finish_offensive(Input.is_key_pressed(KEY_SHIFT))
		"fallback":
			_finish_fallback()


func _end_stroke() -> void:
	_drawing = false
	_editing = ""
	_stroke.clear()
	get_tree().call_group("army_layer", "set_draft", [] as Array[int])


func _mine(province: int) -> bool:
	return province > 0 and GameState.province_controller[province] == GameState.player_tag


func _add_to_stroke(province: int) -> void:
	if province < 1 or _stroke.has(province):
		return
	if tool == "offensive":
		if _mine(province):
			return
		_stroke.append(province)
	elif tool == "fallback":
		if not _mine(province):
			return
		if not _stroke.is_empty() and not Military.neighbors(_stroke.back()).has(province):
			# A quick drag skips provinces: the line goes the short way between them, over your own ground.
			for p in Military.find_path(GameState, GameState.player_tag, 15.0, _stroke.back(), province):
				if _mine(p) and not _stroke.has(p):
					_stroke.append(p)
		if not _stroke.has(province):
			_stroke.append(province)
	get_tree().call_group("army_layer", "set_draft", _stroke.duplicate(), "line" if tool == "fallback" else "path")


func _assign(front_id: int) -> void:
	var ids: Array[int] = []
	for r in roots():
		ids.append(r.id)
	if not ids.is_empty():
		GameState.issue(AssignToFront.new(GameState.player_tag, front_id, ids))


# ------------------------------------------------------------------ the tools

## The front along the border clicked: the nation across it (the one at war, if there are several), the stretch there,
## or with Shift the whole border. A front that already holds it is reused.
func _front_at(province: int, shift: bool) -> void:
	var me := GameState.player_tag
	if province < 1:
		return
	var other := ""
	if not _mine(province):
		other = GameState.province_controller[province]
	else:
		for n: int in Military.neighbors(province):
			var holder: String = GameState.province_controller[n]
			if holder != me and (other == "" or GameState.at_war(me, holder) and not GameState.at_war(me, other)):
				other = holder
	if other == "" or other == me:
		_say("Click on a border with another nation.")
		return
	var anchor := 0 if shift else province
	var front: Front = null
	var stretch := Military.border_stretch(Military.border_provinces(GameState, me, other), anchor)
	for f: Front in GameState.fronts.values():
		if f.tag == me and f.against == other and (f.anchor == 0) == (anchor == 0) and (anchor == 0 or f.provinces == stretch):
			front = f
	if front == null:
		var make := DesignateFront.new(me, "", [] as Array[int], other, "line", anchor)
		if not GameState.issue(make):
			_say(DesignateFront.problem(GameState, me, [] as Array[int], other))
			return
		front = GameState.fronts[make.front_id]
	_assign(front.id)
	set_tool("")


func _finish_offensive(as_phase: bool) -> void:
	var line := _stroke.duplicate()
	_end_stroke()
	if line.is_empty():
		return
	var made := 0
	for root in roots():
		if root.front_id == 0:
			continue
		var o := Offensives.of_army(GameState, root)
		if as_phase and o != null and o.kind == "broad":
			made += int(GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "phase", line)))
		else:
			made += int(GameState.issue(PlanOffensive.new(GameState.player_tag, root.id, "broad", line, aggressiveness)))
	if made == 0:
		_say("Put the army on a front first (Create/Edit front line).")
	set_tool("")


func _spearhead_at(province: int) -> void:
	if province < 1 or _mine(province):
		_say("Click an enemy province to break through at.")
		return
	for root in roots():
		if root.front_id != 0:
			GameState.issue(PlanOffensive.new(GameState.player_tag, root.id, "spearhead", [province] as Array[int], aggressiveness))
	set_tool("")


func _finish_fallback() -> void:
	var line := _stroke.duplicate()
	_end_stroke()
	if line.is_empty():
		return
	var make := DesignateFront.new(GameState.player_tag, "", line)
	if GameState.issue(make):
		_assign(make.front_id)
		set_tool("")
	else:
		_say(DesignateFront.problem(GameState, GameState.player_tag, line))


## Add to front line: the front clicked (a border front also from the enemy side; a plan's target stands for its army's
## front) takes the selected armies.
func _add_at(province: int) -> void:
	var hit := order_at(province)
	var front: Front = hit.get("front")
	if front == null and hit.has("plan"):
		var owner: Army = GameState.armies.get((hit.plan as Offensive).army_id)
		front = GameState.fronts.get(owner.front_id) if owner != null else null
	if front == null:
		_say("Click one of your fronts.")
		return
	_assign(front.id)
	set_tool("")


## A garrison click: the ticked kinds near the province, or the province itself (again: taken off).
func _garrison_at(province: int) -> void:
	if not _mine(province):
		_say("A garrison guards provinces you hold.")
		return
	var kinds: Array[String] = []
	for k: String in _garrison_checks:
		if _garrison_checks[k].button_pressed:
			kinds.append(k)
	if _stroke.has(province):
		_stroke.erase(province)
	elif kinds.is_empty():
		_stroke.append(province)
	else:
		var found := 0
		for p in area_of(province, AREA_HOPS):
			if not _stroke.has(p) and kinds.any(func(k: String) -> bool: return guards(p, k)):
				_stroke.append(p)
				found += 1
		if found == 0:
			_say("Nothing ticked lies within %d provinces of %s." % [AREA_HOPS, MapData.provinces[province].name])
	get_tree().call_group("army_layer", "set_draft", _stroke.duplicate(), "area")


## The nation's own provinces within `hops` of a province.
func area_of(province: int, hops: int) -> Array[int]:
	var out: Array[int] = [province]
	var ring: Array[int] = [province]
	for i in hops:
		var next: Array[int] = []
		for p in ring:
			for n: int in Military.neighbors(p):
				if _mine(n) and not out.has(n):
					out.append(n)
					next.append(n)
		ring = next
	return out


## Whether a province is one of a kind a garrison can guard.
func guards(province: int, kind: String) -> bool:
	match kind:
		"port":
			return Navy.port_level(GameState, province) > 0
		"fort":
			return int(GameState.province_buildings[province].get("fortification", 0)) > 0
		"city":
			return GameState.cities.any(func(c) -> bool: return c.province == province)
		"capital":
			return GameState.nations[GameState.player_tag].capital == province
	return false


func finish_garrison() -> void:
	if tool != "garrison":
		return
	if _stroke.is_empty():
		_say("Click the provinces to guard first.")
		return
	var make := DesignateFront.new(GameState.player_tag, "", _stroke.duplicate(), "", "garrison")
	if GameState.issue(make):
		_assign(make.front_id)
		set_tool("")
	else:
		_say(DesignateFront.problem(GameState, GameState.player_tag, _stroke, "", "garrison"))


func _invasion_at(province: int) -> void:
	if province < 1:
		return
	if _port == 0:
		if not _mine(province) or Navy.port_level(GameState, province) <= 0:
			_say("Click a port of yours to sail from.")
			return
		_port = province
		get_tree().call_group("army_layer", "set_draft", [province] as Array[int], "area")
		_update_hint()
		return
	var made := 0
	var why := ""
	for root in roots():
		why = PlanOffensive.problem(GameState, GameState.player_tag, root.id, "invasion", [province] as Array[int], aggressiveness, _port)
		if why.is_empty():
			made += int(GameState.issue(PlanOffensive.new(GameState.player_tag, root.id, "invasion", [province] as Array[int], aggressiveness, _port)))
	if made == 0:
		_say(why if not why.is_empty() else "Choose a coastal province to land on.")
		return
	set_tool("")


func _warship_fleets() -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in Navy.fleets_of(GameState, GameState.player_tag):
		if f.fighting or not Navy.armies_aboard(GameState, f).is_empty():
			continue
		for s: Ship in f.ships:
			if int(Navy.cfg.types[s.type].get("capacity", 0)) == 0:
				out.append(f)
				break
	return out


## Naval support: the free warship fleet nearest by sea sails to the zone off the coast clicked (or the zone clicked)
## and stays there on Shore support.
func _support_at(province: int, zone: int) -> void:
	var zones: Array = [zone] if zone > 0 else (MapData.zones_of_port(province) if province > 0 else [])
	if zones.is_empty():
		_say("Click a coast or the sea off it.")
		return
	var best: Fleet = null
	var best_days := INF
	var best_zone := 0
	for f in _warship_fleets():
		var from: Array = [f.current_zone()] if f.current_zone() > 0 else MapData.zones_of_port(f.port)
		var path := Navy.find_path(f.speed(), from, zones)
		if path.is_empty() and not zones.has(f.current_zone()):
			continue
		var days := Navy.path_days(f.speed(), path)
		if days < best_days:
			best_days = days
			best = f
			best_zone = path[-1] if not path.is_empty() else f.current_zone()
	if best == null:
		_say("None of your warships can reach that coast.")
		return
	if best.current_zone() != best_zone or best.is_in_port():
		GameState.issue(MoveFleet.new(GameState.player_tag, best.id, best_zone))
	GameState.issue(SetFleetMission.new(GameState.player_tag, best.id, "support"))
	get_tree().call_group("event_feed", "say", "%s sails to support the attack there." % best.display_name, Fmt.GOOD)
	set_tool("")


# ------------------------------------------------------------------ reshaping (Create/Edit, Attack line, Edit order)

## Edit order: the selected army's target line (a spearhead's or a landing's target moves to the province clicked), else
## its drawn line.
func _edit_at(province: int) -> void:
	if province < 1:
		return
	var rs := roots()
	var o := Offensives.of_army(GameState, rs[0]) if not rs.is_empty() else null
	if o != null and not o.done:
		if o.kind != "broad":
			if not GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "targets", [province] as Array[int])):
				_say("That cannot be the target.")
			return
		_begin_edit("plan", o.targets(), province)
		return
	var f := _drawn_front()
	if f != null:
		_begin_edit("front", f.provinces, province)
		return
	if not rs.is_empty() and rs[0].front_id != 0:
		_say("This front follows the border: Create/Edit front line takes a stretch of it (click) or all of it (Shift+click).")
	else:
		_say("The selected army has no order to edit.")


## The first selected army's line drawn by hand (not a border front, not a garrison), or null.
func _drawn_front() -> Front:
	var rs := roots()
	if rs.is_empty():
		return null
	var f: Front = GameState.fronts.get(rs[0].front_id)
	return f if f != null and f.against.is_empty() and f.kind == "line" else null


## Whether a click starts on a drawn line or just beyond one of its ends.
func _touches_line(f: Front, province: int) -> bool:
	if province < 1 or f.provinces.is_empty():
		return false
	if f.provinces.has(province):
		return true
	return _mine(province) and (Military.neighbors(f.provinces.front()).has(province) or Military.neighbors(f.provinces.back()).has(province))


## The first selected army's broad push, or null.
func _broad_plan() -> Offensive:
	var rs := roots()
	if rs.is_empty():
		return null
	var o := Offensives.of_army(GameState, rs[0])
	return o if o != null and o.kind == "broad" and not o.done else null


## Starts reshaping a line. Starting off it adds what the drag crosses; starting on it, the drag decides: on to new
## provinces adds them (a line's end dragged outward), over the line takes them off; a click alone takes off the one
## clicked.
func _begin_edit(what: String, line: Array[int], province: int) -> void:
	_editing = what
	_stroke = line.duplicate()
	_drawing = true
	_press = province
	_edit_mode = "" if _stroke.has(province) else "add"
	if _edit_mode == "add":
		_edit_touch(province)


func _edit_touch(province: int) -> void:
	if _edit_mode == "":
		if province == _press:
			return
		_edit_mode = "add" if not _stroke.has(province) else "remove"
		if _edit_mode == "remove":
			_take_off(_press)
	if _edit_mode == "remove":
		_take_off(province)
	else:
		_put_on(province)
	get_tree().call_group("army_layer", "set_draft", _stroke.duplicate(), "path")


## Takes a province off the line being reshaped (a drawn line only from its ends).
func _take_off(province: int) -> void:
	if not _stroke.has(province):
		return
	if _editing == "front" and province != _stroke.front() and province != _stroke.back():
		return
	_stroke.erase(province)


## Puts a province on the line being reshaped (a drawn line only at its ends, on your own ground).
func _put_on(province: int) -> void:
	var is_line := _editing == "front"
	if not _stroke.has(province):
		if is_line:
			if not _mine(province):
				return
			if _stroke.is_empty() or Military.neighbors(_stroke.back()).has(province):
				_stroke.append(province)
			elif Military.neighbors(_stroke.front()).has(province):
				_stroke.insert(0, province)
			else:
				return
		elif not _mine(province):
			_stroke.append(province)


func _edit_finish() -> void:
	if _edit_mode == "":
		_take_off(_press)
	var what := _editing
	var line := _stroke.duplicate()
	set_tool("")
	if line.is_empty():
		_say("An order needs at least one province; use Delete to remove it.")
		return
	if what == "plan":
		var o := _broad_plan()
		if o != null:
			GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "targets", line))
	else:
		var f := _drawn_front()
		if f != null and not GameState.issue(SetFrontLine.new(GameState.player_tag, f.id, line)):
			_say(SetFrontLine.problem(GameState, GameState.player_tag, f.id, line))


# ------------------------------------------------------------------ delete

## The order on the map at a province: a plan aiming at it (or a landing sailing from it), else a front through it
## (a border front also from the enemy side of the border). The selected armies' orders come first. {} if none.
func order_at(province: int) -> Dictionary:
	if province < 1:
		return {}
	var mine := {}
	for r in roots():
		mine[r.id] = true
	var plans: Array = GameState.offensives.values()
	plans.sort_custom(func(a: Offensive, b: Offensive) -> bool: return mine.has(a.army_id) and not mine.has(b.army_id))
	for o: Offensive in plans:
		if o.tag == GameState.player_tag and not o.done and (o.targets().has(province) or o.port == province):
			return {"plan": o}
	var fronts: Array = GameState.fronts.values()
	fronts.sort_custom(func(a: Front, b: Front) -> bool: return a.army_ids.any(func(id: int) -> bool: return mine.has(id)) and not b.army_ids.any(func(id: int) -> bool: return mine.has(id)))
	for f: Front in fronts:
		if f.tag != GameState.player_tag:
			continue
		if f.provinces.has(province):
			return {"front": f}
		if not f.against.is_empty() and GameState.province_controller[province] == f.against:
			for n: int in Military.neighbors(province):
				if f.provinces.has(n):
					return {"front": f}
	return {}


func _delete_at(province: int) -> void:
	var hit := order_at(province)
	if hit.is_empty():
		_say("No order there.")
		return
	if hit.has("plan"):
		GameState.issue(SetOffensive.new(GameState.player_tag, (hit.plan as Offensive).id, "cancel"))
		return
	var f: Front = hit.front
	# The plans of the armies on it go with it.
	for id in f.army_ids:
		var o := Offensives.of_army(GameState, GameState.armies.get(id)) if GameState.armies.has(id) else null
		if o != null:
			GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "cancel"))
	GameState.issue(DeleteFront.new(GameState.player_tag, f.id))


## Right click on Delete: every order of the selected armies, or with none selected every front and plan of yours.
func clear_all_orders() -> void:
	var me := GameState.player_tag
	var rs := roots()
	if not rs.is_empty():
		_on_unassign()
		get_tree().call_group("event_feed", "say", "The selected armies' orders are cleared.", Fmt.GOOD)
		return
	for o: Offensive in GameState.offensives.values().duplicate():
		if o.tag == me:
			GameState.issue(SetOffensive.new(me, o.id, "cancel"))
	for f: Front in GameState.fronts.values().duplicate():
		if f.tag == me:
			GameState.issue(DeleteFront.new(me, f.id))
	get_tree().call_group("event_feed", "say", "Every front and plan of yours is cleared.", Fmt.GOOD)


# ------------------------------------------------------------------ the buttons

func _on_execute() -> void:
	var plans := _plans()
	if plans.is_empty():
		_refresh()
		return
	var launch := not plans.all(func(o: Offensive) -> bool: return o.active)
	for o in plans:
		if o.active != launch:
			GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "launch", launch))
	_refresh()



func _on_train() -> void:
	var ids: Array[int] = []
	for r in roots():
		ids.append(r.id)
	if ids.is_empty():
		return
	var on := not roots().all(func(r: Army) -> bool: return r.training)
	GameState.issue(SetTraining.new(GameState.player_tag, ids, on))
	_refresh()


## Goes round Careful, Balanced and Aggressive, for the selected plans and the plans to come.
func _on_aggressiveness() -> void:
	var keys: Array = AGGRESSIVENESS.map(func(a: Array) -> String: return a[0])
	aggressiveness = keys[(maxi(0, keys.find(aggressiveness)) + 1) % keys.size()]
	for o in _plans():
		GameState.issue(SetOffensive.new(GameState.player_tag, o.id, "aggressiveness", aggressiveness))
	_refresh()


func _on_unassign() -> void:
	var me := GameState.player_tag
	var ids: Array[int] = []
	for r in roots():
		var o := Offensives.of_army(GameState, r)
		if o != null:
			GameState.issue(SetOffensive.new(me, o.id, "cancel"))
		if r.front_id != 0:
			ids.append(r.id)
	if not ids.is_empty():
		GameState.issue(AssignToFront.new(me, 0, ids))
	_refresh()
