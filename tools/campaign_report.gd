extends SceneTree
## AI-only run that measures what PLAN.md's steps are judged by, and prints them as one line of JSON ("RESULT {...}")
## for tools/campaign.py to gather over many seeds. The bystander is the player's nation: its armies stand still, and
## every decision put to it is answered as the AI would answer it (events by their ai_option, crises by
## Crisis.choose_response, calls to arms by AIDiplomacy.joins, peace offers by AIPeace.accepts), so it is a passive
## player rather than a hole in the map.
## Run: godot --headless --path . -s res://tools/campaign_report.gd -- [scenario_dir] [years] [ai_seed] [bystander] [verbose]
##
## What it measures:
##   first_gp_war        year.month of the first war between two great powers (Pressure.GREAT), or 0
##   gp_war_months       how long every war between two great powers lasted, in months (still running: to the end)
##   fra_ger_months      the same for France and Germany alone
##   capitals_ceded      capitals that changed owner while the nation kept other provinces
##   detached_ceded      provinces that changed owner with no land path (through that day's other changes) to land
##                       the new owner held the day before
##   worst_gp_loss       the largest share of a great power's provinces lost on one day
##   post_wars_per_year, post_crises_per_year, post_tension_sd   from POST_FROM (1922, after the great war's tail) on:
##                       declarations and crises opened a year, and the spread of January tension
##   treasury_months     median treasury of the great powers at peace, in months of revenue (sampled monthly); and
##   treasury_months_late the same from POST_FROM on
##   demob_ratio         median men in units over the most men the nation had in its last war, great powers at peace
##                       three years after it (1.0: nobody went home)
##   focus_idle_max      the longest run of months an AI nation spent with no focus (after its first year)
##   bystander_decisions decisions put to the bystander a year

const POST_FROM := 1922


func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var Pr = load("res://scripts/sim/pressure.gd")
	var Cr = load("res://scripts/sim/crisis.gd")
	var AD = load("res://scripts/ai/ai_diplomacy.gd")
	var AP = load("res://scripts/ai/ai_peace.gd")
	var Mil = load("res://scripts/sim/military.gd")
	var AnswerEv = load("res://scripts/sim/answer_event.gd")
	var AnswerJn = load("res://scripts/sim/answer_join.gd")
	var AnswerPc = load("res://scripts/sim/answer_peace.gd")
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://data/scenarios/jan_1900/"
	var years := int(args[1]) if args.size() > 1 else 20
	var seed := int(args[2]) if args.size() > 2 else 0
	var me: String = args[3] if args.size() > 3 else "ESP"
	var verbose := args.size() > 4
	gs.load_scenario(dir)
	gs.ai_enabled = true
	gs.ai_seed = seed
	gs.set_player(me)
	var great: Array = Pr.GREAT
	var start_year: int = clock.year

	var first_gp_war := [0.0]
	var declarations := {}
	var crises := {}
	var decisions := [0]
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		if not at_war:
			return
		declarations[clock.year] = int(declarations.get(clock.year, 0)) + 1
		if a in great and b in great and first_gp_war[0] == 0.0:
			first_gp_war[0] = clock.year + clock.month / 100.0
		if verbose:
			print("%d-%02d war %s -> %s" % [clock.year, clock.month, a, b]))
	gs.crisis_opened.connect(func(c: Dictionary) -> void:
		crises[clock.year] = int(crises.get(clock.year, 0)) + 1
		if verbose:
			print("%d-%02d crisis %s" % [clock.year, clock.month, c.title]))
	gs.event_posted.connect(func(_d: Dictionary) -> void: decisions[0] += 1)
	var changes: Array = []
	gs.province_owner_changed.connect(func(id: int, old: String, new: String) -> void: changes.append([id, old, new]))

	var capitals_ceded := [0]
	var detached := [0]
	var worst_loss := [0.0, ""]
	var treasury_samples: Array = []
	var treasury_late: Array = []
	var army_samples: Array = []
	var war_peak := {}
	var idle_run := {}
	var idle_max := [0, ""]
	var tension_jan := {}

	for d in years * 365:
		var owners_before: PackedStringArray = gs.province_owner.duplicate()
		var capitals := {}
		var counts := {}
		for tag: String in gs.nations:
			capitals[tag] = gs.nations[tag].capital
			counts[tag] = gs.nations[tag].provinces.size()
		changes.clear()
		clock.advance_day()
		_answer(gs, me, Pr, Cr, AD, AP, AnswerEv, AnswerJn, AnswerPc)
		if not changes.is_empty():
			_measure_changes(gs, Mil, changes, owners_before, capitals, counts, great, capitals_ceded, detached, worst_loss, verbose, clock)
		if clock.day == 1:
			if clock.month == 1:
				tension_jan[clock.year] = gs.tension
			_sample_month(gs, me, great, clock, treasury_samples, treasury_late, army_samples, war_peak, idle_run, idle_max, start_year)

	var gp_months: Array = []
	var fra_ger: Array = []
	var all_wars: Array = gs.war_history.duplicate()
	all_wars.append_array(gs.wars.values())
	for w in all_wars:
		if w.a in great and w.b in great:
			var end: int = w.end_day if w.end_day > 0 else clock.days_elapsed
			var months := snappedf((end - w.start_day) / 30.4, 0.1)
			gp_months.append(months)
			if (w.a == "FRA" and w.b == "GER") or (w.a == "GER" and w.b == "FRA"):
				fra_ger.append(months)
	var post_years := 0
	var post_wars := 0
	var post_crises := 0
	var post_tension: Array = []
	for y in range(POST_FROM, clock.year + 1):
		if y < start_year:
			continue
		post_years += 1
		post_wars += int(declarations.get(y, 0))
		post_crises += int(crises.get(y, 0))
		if tension_jan.has(y):
			post_tension.append(tension_jan[y])
	var result := {
		"scenario": dir.get_base_dir().get_file(), "seed": seed, "years": years, "bystander": me, "end": "%d-%02d" % [clock.year, clock.month],
		"first_gp_war": first_gp_war[0],
		"gp_war_months": gp_months, "gp_war_months_median": _median(gp_months),
		"fra_ger_months": fra_ger,
		"capitals_ceded": capitals_ceded[0], "detached_ceded": detached[0],
		"worst_gp_loss": snappedf(worst_loss[0], 0.01), "worst_gp_loss_who": worst_loss[1],
		"post_years": post_years,
		"post_wars_per_year": snappedf(float(post_wars) / maxf(post_years, 1), 0.01) if post_years > 0 else null,
		"post_crises_per_year": snappedf(float(post_crises) / maxf(post_years, 1), 0.01) if post_years > 0 else null,
		"post_tension_sd": snappedf(_sd(post_tension), 0.1) if post_tension.size() > 1 else null,
		"treasury_months": snappedf(_median(treasury_samples), 0.1),
		"treasury_months_late": snappedf(_median(treasury_late), 0.1) if not treasury_late.is_empty() else null,
		"demob_ratio": snappedf(_median(army_samples), 0.01) if not army_samples.is_empty() else null,
		"focus_idle_max": idle_max[0], "focus_idle_who": idle_max[1],
		"bystander_decisions": snappedf(decisions[0] / float(years), 0.01),
		"wars_by_year": declarations, "crises_by_year": crises,
	}
	print("RESULT " + JSON.stringify(result))
	quit()


## Answers what is waiting for the bystander as the AI would.
func _answer(gs: Node, me: String, Pr, Cr, AD, AP, AnswerEv, AnswerJn, AnswerPc) -> void:
	for guard in 8:
		if gs.pending_events.is_empty():
			break
		var e: Dictionary = gs.pending_events[0]
		var option := 0
		var ev: String = str(e.event)
		if ev.begins_with("crisis:"):
			var c: Dictionary = Cr.find(gs, int(ev.get_slice(":", 1)))
			if not c.is_empty():
				var want: String = Cr.choose_response(gs, c)
				for i in e.options.size():
					for fx: Dictionary in e.options[i].effects:
						if fx.has("crisis") and fx.crisis[1] == want:
							option = i
		else:
			for def: Dictionary in Pr.events:
				if def.id == ev and def.has("ai_option"):
					option = mini(Pr._pick(gs, def.ai_option), e.options.size() - 1)
		if not gs.issue(AnswerEv.new(e.id, option)):
			gs.pending_events.remove_at(0)
	for j: Dictionary in gs.pending_joins.duplicate():
		gs.issue(AnswerJn.new(j.id, AD.joins(gs, j)))
	for o: Dictionary in gs.pending_offers.duplicate():
		if o.to == me:
			gs.issue(AnswerPc.new(o.id, AP.accepts(gs, o)))


## The changes of owner of one day: capitals, provinces cut off from the new owner's land, and the worst loss.
func _measure_changes(gs: Node, Mil, changes: Array, owners_before: PackedStringArray, capitals: Dictionary, counts: Dictionary,
		great: Array, capitals_ceded: Array, detached: Array, worst_loss: Array, verbose: bool, clock: Node) -> void:
	var by_new := {}
	var by_old := {}
	for ch: Array in changes:
		var id: int = ch[0]
		var old: String = ch[1]
		var new: String = ch[2]
		by_new[new] = by_new.get(new, []) + [id]
		by_old[old] = int(by_old.get(old, 0)) + 1
		if id == capitals.get(old, -1) and not gs.nations[old].provinces.is_empty():
			capitals_ceded[0] += 1
			if verbose:
				print("%d-%02d capital of %s ceded to %s" % [clock.year, clock.month, old, new])
	for new: String in by_new:
		var ids: Array = by_new[new]
		for id: int in ids:
			if not _linked(Mil, id, ids, owners_before, new):
				detached[0] += 1
				if verbose:
					print("%d-%02d detached: province %d to %s" % [clock.year, clock.month, id, new])
	for old: String in by_old:
		if old in great and int(counts.get(old, 0)) > 0:
			var share := float(by_old[old]) / float(counts[old])
			if share > worst_loss[0]:
				worst_loss[0] = share
				worst_loss[1] = "%s %d-%02d" % [old, clock.year, clock.month]


## Whether `id` reaches land `tag` held before, by land, through the provinces it gained the same day.
func _linked(Mil, id: int, gained: Array, owners_before: PackedStringArray, tag: String) -> bool:
	var seen := {id: true}
	var queue: Array = [id]
	while not queue.is_empty():
		var p: int = queue.pop_back()
		for n: int in Mil.neighbors(p):
			if owners_before[n] == tag:
				return true
			if n in gained and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return false


## Monthly samples: treasuries and armies of the great powers at peace, and the AI nations' idle foci. `war_peak` holds
## each great power's most men in units during its current or last war.
func _sample_month(gs: Node, me: String, great: Array, clock: Node, treasury_samples: Array, treasury_late: Array,
		army_samples: Array, war_peak: Dictionary, idle_run: Dictionary, idle_max: Array, start_year: int) -> void:
	for tag: String in great:
		if not gs.nations.has(tag) or gs.nations[tag].provinces.is_empty():
			continue
		var n = gs.nations[tag]
		if not gs.wars_of(tag).is_empty():
			var peak: Dictionary = war_peak.get(tag, {"men": 0, "at_war": false})
			if not peak.at_war:
				peak = {"men": 0, "at_war": true}
			peak.men = maxi(peak.men, n.men_in_units)
			war_peak[tag] = peak
			continue
		if war_peak.has(tag):
			war_peak[tag].at_war = false
		var monthly: float = float(n.budget.get("revenue", 0.0)) / 12.0
		if monthly > 0.0:
			treasury_samples.append(n.treasury / monthly)
			if clock.year >= POST_FROM:
				treasury_late.append(n.treasury / monthly)
		var last_end := -1
		for w in gs.war_history:
			if w.a == tag or w.b == tag:
				last_end = maxi(last_end, w.end_day)
		if last_end >= 0 and clock.days_elapsed - last_end >= 3 * 365 and war_peak.has(tag) and war_peak[tag].men > 0:
			army_samples.append(float(n.men_in_units) / float(war_peak[tag].men))
	if clock.year <= start_year:
		return
	for tag: String in gs.nations:
		if tag == me or gs.nations[tag].provinces.is_empty():
			continue
		if gs.nations[tag].focus.is_empty():
			idle_run[tag] = int(idle_run.get(tag, 0)) + 1
			if idle_run[tag] > idle_max[0]:
				idle_max[0] = idle_run[tag]
				idle_max[1] = tag
		else:
			idle_run[tag] = 0


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	var m := s.size() / 2
	return float(s[m]) if s.size() % 2 == 1 else (float(s[m - 1]) + float(s[m])) / 2.0


func _sd(values: Array) -> float:
	var mean := 0.0
	for v in values:
		mean += float(v)
	mean /= values.size()
	var acc := 0.0
	for v in values:
		acc += (float(v) - mean) * (float(v) - mean)
	return sqrt(acc / values.size())
