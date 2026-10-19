extends SceneTree
## Headless test of the command panel's cards: a click on a card is marked as used before its
## handler runs. The handlers rebuild the panel and take the card out of the tree, after which it
## could no longer mark the click as used, and it fell through to the map and selected the
## province under the panel (and dropped the army that had just been picked).
## Run: godot --headless --path . -s res://tests/command_card_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var Card = load("res://scripts/ui/command_card.gd")
	var holder := Control.new()
	root.add_child(holder)
	var card: Control = Card.new()
	holder.add_child(card)
	await process_frame
	var seen := {"left": false, "right": false, "pressed": 0}
	card.pressed.connect(func(_shift: bool) -> void:
		seen.pressed += 1
		seen.left = root.is_input_handled()
		holder.remove_child(card))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._gui_input(click)
	_check(seen.pressed == 1 and seen.left, "a left click is accepted before the handler runs, even if the handler removes the card")
	holder.add_child(card)
	card.context_requested.connect(func(_at: Vector2) -> void:
		seen.right = root.is_input_handled()
		holder.remove_child(card))
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	card._gui_input(right)
	_check(seen.right, "and so is a right click")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
