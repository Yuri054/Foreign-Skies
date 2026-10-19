extends SceneTree
## Prints each nation's resource flows at the start of the scenario, in units a day: what it
## makes and uses, what it imports, how many civilian factories the imports lock, and its
## construction capacity. Used to calibrate data/economy.json ("flows") and the equipment costs.
## Run: godot --headless --path . -s res://tools/flows_report.gd [-- TAG ...]


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var Eco = load("res://scripts/sim/economy.gd")
	var Fl = load("res://scripts/sim/flows.gd")
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var ids: Array = Eco.resource_ids()
	var tags: Array = gs.nations.keys()
	tags.sort()
	print("tag\tCIC\tMIC\tIC/day\tlock")
	for tag: String in tags:
		if not only.is_empty() and tag not in only:
			continue
		var n = gs.nations[tag]
		var b: Dictionary = n.budget
		print("%s\t%d\t%d\t%.0f\t%.1f" % [tag, b.factories, b.military_factories, b.construction_points, b.trade_lock])
		for r: String in ids:
			var info: Dictionary = b.resources[r]
			print("   %-14s make %7.1f  use %7.1f  balance %7.1f  import %6.1f  export %6.1f  stock %7.0f  short %4.0f%%" % [
					r, Fl.units(r, info.production), Fl.units(r, info.demand), Fl.units(r, info.balance), Fl.units(r, info.imported),
					Fl.units(r, info.exported), info.stock, info.shortage * 100.0])
	quit()
