extends SceneTree
## Plays the scenario forward with nobody at the controls and prints what happens: wars,
## calls to arms, joins, alarms, peace, and a weekly snapshot of mobilization, treasuries and
## war support. Used to balance the 1914 crisis.
## Run: godot --headless --path . -s res://tools/crisis_report.gd -- [days] [player]
##   days    how long to run (default 120)
##   player  tag of the nation the player is meant to be (default ESP, a bystander)
##   quiet   as a third argument, starts with no war at all: nothing should happen

var gs: Node
var clock: Node
var D


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	D = load("res://scripts/sim/diplomacy.gd")
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 120
	var player: String = args[1] if args.size() > 1 else "ESP"
	gs.set_player(player)
	if args.size() > 2 and args[2] == "quiet":
		gs.wars.clear()
		gs.join_calls.clear()
	_connect()
	print("Start: %s, player %s" % [clock.date_string(), player])
	_snapshot()
	for i in days:
		clock.advance_day()
		if gs.has_pending():
			_decide()
		if (i + 1) % 14 == 0:
			_snapshot()
	print("End: %s" % clock.date_string())
	_summary()
	quit()


func _name(tag: String) -> String:
	return gs.nations[tag].display_name


func _log(text: String) -> void:
	print("[%s] %s" % [clock.date_string(), text])


func _connect() -> void:
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		var war = gs.war_between(a, b) if at_war else (gs.war_history.back() if not gs.war_history.is_empty() else null)
		var cb: String = war.casus_belli if war != null and at_war else ""
		_log("%s %s %s%s" % [a, "declares on" if at_war else "makes peace with", b, " (%s)" % cb if cb != "" else ""])
	)
	gs.join_called.connect(func(d: Dictionary) -> void: _log("  %s called to join %s (%s)" % [d.tag, d.ally, d.kind]))
	gs.join_resolved.connect(func(d: Dictionary, joined: bool) -> void:
		if not joined:
			_log("  %s declines (%s, ally %s%s)" % [d.tag, d.kind, d.ally, ", conflict" if d.conflict else ""])
	)
	gs.mobilization_alarm.connect(func(a: String, b: String) -> void: _log("  %s alarms %s" % [a, b]))
	gs.treaty_changed.connect(func(t, added: bool) -> void: _log("  %s %s %s-%s" % [t.kind, "signed" if added else "ended", t.a, t.b]))
	gs.peace_resolved.connect(func(o: Dictionary, accepted: bool) -> void:
		_log("  peace %s -> %s: %s (%d demands)" % [o.from, o.to, "accepted" if accepted else "refused", o.demands.size()]))


## The player's own pending decisions are answered as the rules suggest: honour bound
## obligations, decline the rest.
func _decide() -> void:
	for d: Dictionary in gs.pending_joins.duplicate():
		gs.issue(load("res://scripts/sim/answer_join.gd").new(d.id, d.kind != "entente" and not d.conflict))
	for o: Dictionary in gs.pending_offers.duplicate():
		gs.issue(load("res://scripts/sim/answer_peace.gd").new(o.id, true))


func _snapshot() -> void:
	var mob: PackedStringArray = []
	var low: PackedStringArray = []
	var support: PackedStringArray = []
	for tag: String in gs.nations:
		var n = gs.nations[tag]
		if n.mobilization >= 0.05:
			mob.append("%s %d%%" % [tag, roundi(n.mobilization * 100.0)])
		if n.treasury < 0.0:
			low.append("%s %.0f" % [tag, n.treasury])
		if gs.at_war(tag, tag) or not gs.wars_of(tag).is_empty():
			support.append("%s %d" % [tag, roundi(n.war_support)])
	_log("snapshot: wars %d | mobilized: %s | war support: %s | negative treasury: %s" % [
			gs.wars.size(), ", ".join(mob), ", ".join(support), ", ".join(low)])


func _summary() -> void:
	var pairs: PackedStringArray = []
	for war in gs.wars.values():
		pairs.append("%s-%s" % [war.a, war.b])
	print("Wars at the end: %s" % ", ".join(pairs))
	print("Wars ended: %d" % gs.war_history.size())
	for tag: String in gs.nations:
		var n = gs.nations[tag]
		print("  %s treasury %.0f, net %+.1f/yr, support %d, mobilization %d%%, prestige %d" % [
				tag, n.treasury, n.budget.net, roundi(n.war_support), roundi(n.mobilization * 100.0), roundi(n.prestige)])
