extends SceneTree
## Saves the two pointers, enlarged on the slate of a window, to look at them. Run:
##   godot --headless --path . -s res://tools/screenshot_cursor.gd -- out.png
func _initialize() -> void:
	await process_frame
	var sheet := Image.create(280, 140, false, Image.FORMAT_RGBA8)
	sheet.fill(UiTheme.SLATE)
	for i in 2:
		var img: Image = UiCursor.arrow_image() if i == 0 else UiCursor.hand_image()
		var big := img.duplicate()
		big.resize(128, 128, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, 128, 128), Vector2i(6 + i * 140, 6))
	sheet.save_png(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://cursor.png")
	quit(0)
