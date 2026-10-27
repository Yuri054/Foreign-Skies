class_name NationScreen
extends FloatingWindow
## The one window for running the player's nation: a strip of tabs along the top (Overview, Economy,
## Build, Military, Navy, Diplomacy, Focus), each tab a page that fills the rest. The pages are
## the game's panels, embedded (FloatingWindow.embed): a page is open (`visible`) while its tab shows
## and the screen is up, so a panel's own checks of `visible` still mean "the player is looking at it".
## Each tab has a letter that opens the screen on it, and that same letter closes it again. Hover
## a tab to see which. The country panel for other nations (right click) stays a window of its own.

## The tabs wrap onto a second row when the window is narrow, so the screen never needs more width than the view has.
var _tabs_row := HFlowContainer.new()
var _stack := PanelContainer.new()
## [{page, title, key, button}] in tab order.
var _pages: Array[Dictionary] = []
var _current: Control = null
var _group := ButtonGroup.new()


func _ready() -> void:
	add_to_group("nation_screen")
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_tabs_row.add_theme_constant_override("h_separation", 3)
	_tabs_row.add_theme_constant_override("v_separation", 3)
	box.add_child(_tabs_row)
	var rule := HSeparator.new()
	box.add_child(rule)
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# A page that needs more room than the screen has scrolls, rather than pushing the window down over the map.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.add_child(_stack)
	box.add_child(scroll)
	add_child(box)
	setup_window("Nation", true, Vector2(800, 560), 0)
	min_window_width = 640.0
	_fit_to_view()
	get_viewport().size_changed.connect(_fit_to_view)
	visibility_changed.connect(func() -> void:
		if not visible:
			for p: Dictionary in _pages:
				p.page.visible = false
	)
	GameState.player_changed.connect(func(_t: String) -> void: _retitle())


## Keeps the screen clear of the top bar and of the map mode bar at the bottom, and inside a small window.
func _fit_to_view() -> void:
	if user_sized or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var room := maxf(view.y - TOP_CLEARANCE - 12.0 - 150.0, 300.0)
	size = Vector2(minf(800.0, maxf(view.x - 40.0, 640.0)), minf(560.0, room))
	position = Vector2(view.x - size.x - 16.0, TOP_CLEARANCE + 12.0)
	_keep_inside.call_deferred()


## A page that needs more width than the window had makes it grow to the right: this brings it back inside the view.
func _keep_inside() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	size.x = minf(size.x, maxf(view.x - 16.0, get_combined_minimum_size().x))
	position.x = clampf(position.x, 8.0, maxf(view.x - size.x - 8.0, 8.0))


## Adds a page as the next tab. `key` is the letter that opens it; the page is a FloatingWindow (embedded
## here) or a plain control with a `toggle` that calls `toggle_page`.
const TAB_ICONS := {"Overview": "shield", "Economy": "scales", "Build": "hammer", "Military": "cannon", "Navy": "anchor", "Diplomacy": "flag", "Focus": "star", "Rankings": "chart", "History": "scroll"}


func add_page(title: String, key: String, page: Control) -> void:
	_stack.add_child(page)
	if page is FloatingWindow:
		(page as FloatingWindow).embed(self)
	else:
		page.set("host", self)
	page.visible = false
	var button := Button.new()
	button.text = title
	button.icon = Icons.get_icon(TAB_ICONS.get(title, ""), 16)
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "%s (%s)" % [title, key]
	button.pressed.connect(func() -> void: open_page(page))
	_tabs_row.add_child(button)
	_pages.append({"page": page, "title": title, "key": key, "button": button})


## The page for a title or a group name, or null.
func page_named(title: String) -> Control:
	for p: Dictionary in _pages:
		if p.title == title:
			return p.page
	return null


func current_page() -> Control:
	return _current if visible else null


## Opens the screen on a page (or on the one for this title).
func open_page(page: Variant) -> void:
	var target: Control = page if page is Control else page_named(str(page))
	if target == null:
		return
	# A spectator runs no nation: only the pages about Europe as a whole open.
	if GameState.get_player() == null and _title_of(target) not in SPECTATOR_PAGES:
		target = page_named(SPECTATOR_PAGES[0])
		if target == null:
			return
	_current = target
	for p: Dictionary in _pages:
		var on: bool = p.page == target
		p.page.visible = on
		(p.button as Button).set_pressed_no_signal(on)
	visible = true
	_retitle()
	move_to_front()
	# A page shows what is true now: its panel works its figures out when it comes up.
	if target.has_method("_refresh"):
		target.call_deferred("_refresh")
	_keep_inside.call_deferred()


## The pages that open with no nation of your own (a spectator).
const SPECTATOR_PAGES := ["Rankings", "History"]


func _title_of(page: Control) -> String:
	for p: Dictionary in _pages:
		if p.page == page:
			return p.title
	return ""


func toggle_page(page: Control) -> void:
	if visible and _current == page:
		close_screen()
	else:
		open_page(page)


func close_screen() -> void:
	if not closable:
		return
	visible = false
	closed.emit()


func _retitle() -> void:
	var n := GameState.get_player()
	var page := ""
	for p: Dictionary in _pages:
		if p.page == _current:
			page = p.title
	title = "%s · %s" % [n.display_name if n != null else "Nation", page] if page != "" else (n.display_name if n != null else "Nation")


## Opens the screen (the page last shown, or the Overview) or closes it: the Nation button of the top bar.
func toggle() -> void:
	if visible:
		close_screen()
	else:
		open_page(_current if _current != null else (_pages[0].page as Control))


## The letters of pages that do not listen for their own letter (the Overview's) open the screen on them;
## pressing the letter of the page showing closes it.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var typed := OS.get_keycode_string(event.keycode).to_upper()
	for p: Dictionary in _pages:
		if p.key == typed and not p.page.has_method("_unhandled_key_input"):
			toggle_page(p.page)
			get_viewport().set_input_as_handled()
			return
