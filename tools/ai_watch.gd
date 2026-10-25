extends SceneTree
## Watches the AI fight: every month a line per great power (armies, what they are doing, campaign, ground held/taken).
## godot --headless --path . -s res://tools/ai_watch.gd -- [scenario_dir] [months] [bystander] [tags comma separated]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var map = root.get_node("MapData")
	var Mil = load("res://scripts/sim/military.gd")
	var AIO = load("res://scripts/ai/ai_offense.gd")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[0] if args.size() > 0 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player(args[2] if args.size() > 2 else "ESP")
	var months := int(args[1]) if args.size() > 1 else 8
	var tags: PackedStringArray = (args[3] if args.size() > 3 else "GER,FRA,AUH,RUS,GBR,ITA").split(",")
	var last := -1
	for d in months * 31:
		clock.advance_day()
		if clock.month == last:
			continue
		last = clock.month
		for tag in tags:
			var n = gs.nations[tag]
			if gs.wars_of(tag).is_empty():
				continue
			var idle := 0
			var moving := 0
			var fighting := 0
			var front := 0
			var camp := 0
			var men := 0.0
			for a in Mil.armies_of(gs, tag):
				men += a.men()
				if a.fighting:
					fighting += 1
				elif not a.path.is_empty():
					moving += 1
				else:
					idle += 1
				if a.front_id != 0:
					front += 1
				if AIO.in_campaign(gs, tag, a.id):
					camp += 1
			var held := 0
			for id in range(1, gs.province_controller.size()):
				if gs.province_controller[id] == tag and gs.province_owner[id] != tag:
					held += 1
			var lost := 0
			for id in n.provinces:
				if gs.province_controller[id] != tag:
					lost += 1
			var c = gs.ai_campaign.get(tag)
			var cs := "-"
			if c != null:
				cs = "%s->%s %s" % [c.enemy, map.provinces[c.target].name, c.phase]
			print("%d-%02d %s support %d armies %d (%dk men) idle %d move %d fight %d front %d camp %d | took %d lost %d | campaign %s" % [
				clock.year, clock.month, tag, n.war_support, Mil.armies_of(gs, tag).size(), men / 1000.0, idle, moving, fighting, front, camp, held, lost, cs])
	quit()
