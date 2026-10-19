extends SceneTree
## Draws the flag pictures: every SVG in assets/flags_src (named by nation tag) becomes a PNG in
## assets/flags, 320 pixels wide. The sources are the flag-icons set (MIT, from npm, 4x3) for the
## nations whose 1914 flag matches today's, and drawn by hand for Germany (the imperial black,
## white and red), Italy (with the Savoy shield), Serbia and Montenegro (the tricolours).
## Run: godot --headless --path . -s res://tools/build_flags.gd
func _initialize() -> void:
	await process_frame
	var dir := DirAccess.open("res://assets/flags_src")
	var done := 0
	for file in dir.get_files():
		if not file.ends_with(".svg"):
			continue
		var buffer := FileAccess.get_file_as_bytes("res://assets/flags_src/" + file)
		var img := Image.new()
		var err := img.load_svg_from_buffer(buffer, 0.5)
		if err != OK:
			printerr("could not draw ", file)
			continue
		img.save_png("res://assets/flags/" + file.get_basename() + ".png")
		done += 1
	print("flags drawn: ", done)
	quit(0)
