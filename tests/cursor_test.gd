extends SceneTree
## Headless test of the in-game pointer: both pictures are drawn in code, the tip of the arrow
## sits on the hotspot, the corners stay clear, and the hand is the gold one.
## Run: godot --headless --path . -s res://tests/cursor_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var arrow: Image = UiCursor.arrow_image()
	var hand: Image = UiCursor.hand_image()
	_check(arrow.get_size() == Vector2i(32, 32) and hand.get_size() == Vector2i(32, 32), "both pointers are 32 by 32")
	_check(arrow.get_pixel(5, 8).a > 0.99 and arrow.get_pixel(31, 0).a == 0.0 and arrow.get_pixel(0, 31).a == 0.0, "the arrow is solid inside and clear at the corners")
	var tip := Vector2i(UiCursor.HOTSPOT)
	_check(arrow.get_pixel(tip.x + 1, tip.y + 2).a > 0.0, "the point of the arrow is at the hotspot")
	var body := arrow.get_pixel(6, 12)
	var gold := hand.get_pixel(13, 12)
	_check(body.b > gold.b + 0.1 and gold.r > gold.b, "the arrow is cream and the pointer over a button gold")
	var finger := Vector2i(UiCursor.HAND_HOTSPOT)
	_check(hand.get_pixel(finger.x, finger.y + 3).a > 0.99 and hand.get_pixel(finger.x - 5, finger.y + 3).a == 0.0, "the hand's finger tip is at its hotspot, with air beside it")
	_check(hand.get_pixel(22, 24).a > 0.99 and arrow.get_pixel(22, 24).a == 0.0, "and the hand is a palm and fingers, not the arrow again")
	_check(UiCursor.arrow_image() == arrow, "the pictures are drawn once")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
