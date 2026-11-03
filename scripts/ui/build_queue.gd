extends PanelContainer
## Always-visible list of the player's buildings under construction, with progress.
## Clicking a row jumps to that province.

signal province_clicked(id: int)

const MAX_ROWS := 8

var _list := VBoxContainer.new()


func _ready() -> void:
	add_to_group("build_queue")
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Bottom-right corner, above the map modes; grows upward.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -306.0
	offset_right = -12.0
	offset_top = -32.0
	offset_bottom = -32.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_list.add_theme_constant_override("separation", 3)
	add_child(_list)

	GameState.economy_updated.connect(_refresh)
	GameState.fleets_changed.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	Clock.day_ticked.connect(_refresh)
	_refresh()


## Stands just above the map modes palette, whatever height its legend and strip give it.
func _process(_delta: float) -> void:
	var palette := get_tree().get_first_node_in_group("map_modes") as Control
	if palette == null or not visible:
		return
	var top := palette.get_global_rect().position.y - get_viewport_rect().size.y - 6.0 if palette.visible else -32.0
	if not is_equal_approx(offset_bottom, top):
		offset_top = top
		offset_bottom = top


func _refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var n := GameState.get_player()
	visible = n != null and not (n.construction.is_empty() and n.shipbuilding.is_empty())
	if not visible:
		return

	# Buildings and ships together, soonest to finish first.
	var jobs: Array[Dictionary] = []
	for job in n.construction:
		jobs.append({"label": Economy.cfg.buildings[job.type].name, "province": job.province, "days_left": job.days_left, "days_total": job.days_total,
				"waiting": not job.started})
	for job in n.shipbuilding:
		jobs.append({"label": Navy.cfg.types[job.type].name, "province": job.province, "days_left": job.days_left, "days_total": job.days_total})
	var title := Label.new()
	title.text = "Under construction (%d)" % jobs.size()
	title.tooltip_text = "Buildings and ships, soonest finished first. \"waiting\" means the project has not started: its province is busy, or the gold or construction points are not there yet."
	_list.add_child(title)
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.days_left < b.days_left)
	for i in mini(jobs.size(), MAX_ROWS):
		_list.add_child(_make_row(jobs[i]))
	if jobs.size() > MAX_ROWS:
		var more := Label.new()
		more.text = "+ %d more" % (jobs.size() - MAX_ROWS)
		more.modulate = Color(1, 1, 1, 0.65)
		_list.add_child(more)


func _make_row(job: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var button := Button.new()
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	var waiting: bool = job.get("waiting", false)
	button.text = "%s, %s  (%s)" % [job.label, MapData.provinces[job.province].name, "waiting" if waiting else "%dd" % job.days_left]
	button.tooltip_text = "Click to go to the province. %s" % ("Waiting to start." if waiting else "Paid for; %d days to go." % job.days_left)
	var id: int = job.province
	button.pressed.connect(func() -> void: province_clicked.emit(id))
	box.add_child(button)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = 1.0
	bar.value = 0.0 if job.get("waiting", false) else 1.0 - float(job.days_left) / maxf(job.days_total, 1.0)
	box.add_child(bar)
	return box
