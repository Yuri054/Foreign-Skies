class_name History
extends RefCounted
## The history of the run, kept whole and written up. Three records are kept in GameState: `history_log` (what
## happened, in order: wars, peaces, events, crises, treaties, collapses), `territory_log` (every change of owner)
## and `history_months` (one row of figures a month). The builders turn them into the sections of the history book
## (timeline, wars, territory, nations, a headline for each month) and into Markdown and HTML for export. Static and
## read-only apart from the recording calls; nothing in the simulation depends on it.

const LOG_MAX := 4000
const TERRITORY_MAX := 3000
const MONTHS_MAX := 1200
const KINDS := {"war": "War", "peace": "Peace", "event": "Event", "crisis": "Crisis", "treaty": "Treaty", "collapse": "Collapse", "ambition": "Ambition"}


# --- Recording ---------------------------------------------------------------------------------

static func load_scenario(gs: Node) -> void:
	gs.history_log.clear()
	gs.territory_log.clear()
	gs.history_months.clear()
	gs.history_counters.clear()


## Writes down something that happened now.
static func note(gs: Node, kind: String, text: String) -> void:
	gs.history_log.append({"day": Clock.days_elapsed, "date": Clock.date_string(), "year": Clock.year, "kind": kind, "text": text})
	if gs.history_log.size() > LOG_MAX:
		gs.history_log.pop_front()


## Replaces the text of the latest note of a kind (a peace first noted plainly is told in full once its terms are known).
static func refine_last(gs: Node, kind: String, text: String) -> void:
	for i in range(gs.history_log.size() - 1, -1, -1):
		if gs.history_log[i].kind == kind:
			gs.history_log[i].text = text
			return


static func record_territory(gs: Node, province: int, old_owner: String, new_owner: String) -> void:
	gs.territory_log.append({"day": Clock.days_elapsed, "date": Clock.date_string(), "year": Clock.year, "province": province,
			"old": old_owner, "new": new_owner})
	gs.history_counters["provinces"] = int(gs.history_counters.get("provinces", 0)) + 1
	if gs.territory_log.size() > TERRITORY_MAX:
		gs.territory_log.pop_front()


## Monthly: one row of figures for the month just ended.
static func step_month(gs: Node) -> void:
	var losses := 0.0
	var battles := 0
	for war: War in gs.wars.values():
		battles += war.battles.size()
		for tag: String in war.losses:
			losses += war.losses[tag]
	for war: War in gs.war_history:
		if Clock.days_elapsed - war.end_day < 62:
			battles += war.battles.size()
			for tag: String in war.losses:
				losses += war.losses[tag]
	var prev_battles: int = gs.history_counters.get("battles_total", 0)
	var prev_losses: float = gs.history_counters.get("losses_total", 0.0)
	# A war that left the books between two months takes its figures with it: never count backwards.
	var row := {"day": Clock.days_elapsed, "year": Clock.year, "month": Clock.month,
			"wars": gs.wars.size(), "battles": maxi(0, battles - prev_battles), "casualties": maxf(0.0, losses - prev_losses),
			"provinces": int(gs.history_counters.get("provinces", 0)), "tension": gs.tension, "crises": gs.crises.size(),
			"top": _top_powers(gs, 3)}
	gs.history_counters["battles_total"] = battles
	gs.history_counters["losses_total"] = losses
	gs.history_counters["provinces"] = 0
	gs.history_months.append(row)
	if gs.history_months.size() > MONTHS_MAX:
		gs.history_months.pop_front()


static func _top_powers(gs: Node, count: int) -> Array:
	var out: Array = []
	for r: Dictionary in Standings.ranking(gs, "industry").slice(0, count):
		out.append(r.tag)
	return out


# --- Reading -----------------------------------------------------------------------------------

## The years the log covers, oldest first.
static func years(gs: Node) -> Array[int]:
	var out: Array[int] = []
	var first: int = gs.scenario.get("start_date", [Clock.year])[0]
	for y in range(first, Clock.year + 1):
		out.append(y)
	return out


## The notes of a year (0 for all of them), each as {date, kind, text}.
static func timeline(gs: Node, year := 0, kinds: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in gs.history_log:
		if (year == 0 or e.year == year) and (kinds.is_empty() or e.kind in kinds):
			out.append(e)
	return out


## A line of figures for a year: the wars, battles and men lost, the provinces that changed hands, the tension at its end
## and the leading powers.
static func year_summary(gs: Node, year: int) -> String:
	var wars := 0
	var battles := 0
	var casualties := 0.0
	var provinces := 0
	var tension := -1.0
	var top: Array = []
	for m: Dictionary in gs.history_months:
		if m.year != year:
			continue
		wars = maxi(wars, m.wars)
		battles += m.battles
		casualties += m.casualties
		provinces += m.provinces
		tension = m.tension
		top = m.top
	if tension < 0.0:
		return "%d: no months recorded." % year
	var line := "%d: tension %d at the year's end" % [year, roundi(tension)]
	if wars > 0:
		line += "; up to %d wars at once, %d battles, %s men lost" % [wars, battles, Fmt.people(casualties)]
	else:
		line += "; no war"
	if provinces > 0:
		line += "; %d provinces changed hands" % provinces
	if not top.is_empty():
		line += "; the leading industries: %s" % ", ".join(top.map(func(t: String) -> String: return gs.nations[t].display_name if gs.nations.has(t) else t))
	return line + "."


## A headline for a month, from its row and the one before: deterministic, with a little variety from the game's seed.
static func headline(gs: Node, year: int, month: int) -> String:
	var row := {}
	var prev := {}
	for i in gs.history_months.size():
		if gs.history_months[i].year == year and gs.history_months[i].month == month:
			row = gs.history_months[i]
			prev = gs.history_months[i - 1] if i > 0 else {}
	if row.is_empty():
		return "No report for this month."
	var variants: Array = []
	if row.casualties >= 20000.0:
		variants = ["%s men fall in a month of war." % Fmt.people(row.casualties), "A bloody month: %s men lost across %d fronts." % [Fmt.people(row.casualties), maxi(row.wars, 1)]]
	elif row.provinces >= 3:
		variants = ["The map is redrawn: %d provinces change hands." % row.provinces, "%d provinces pass to new masters this month." % row.provinces]
	elif row.wars > 0:
		variants = ["War goes on: %d in the field." % row.wars, "The guns are not silent: %d wars burn." % row.wars]
	elif not prev.is_empty() and row.tension - prev.tension >= 4.0:
		variants = ["Tension climbs to %d." % roundi(row.tension), "Europe grows uneasy: tension %d." % roundi(row.tension)]
	elif not prev.is_empty() and prev.tension - row.tension >= 4.0:
		variants = ["Tension eases to %d." % roundi(row.tension), "The chancelleries breathe again: tension %d." % roundi(row.tension)]
	elif row.crises > 0:
		variants = ["A crisis hangs over the powers.", "Diplomats work against the clock."]
	else:
		variants = ["A quiet month in Europe.", "Little to report: the peace holds."]
	return variants[absi(("%d|%d|%d" % [gs.ai_seed, year, month]).hash()) % variants.size()]


## The wars of the run as {title, lines}: when, why, who won what, the battles and the losses.
static func wars_section(gs: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Array = gs.war_history.duplicate()
	all.append_array(gs.wars.values())
	for war: War in all:
		var a: String = gs.nations[war.a].display_name
		var b: String = gs.nations[war.b].display_name
		var lines: PackedStringArray = []
		var cb := ""
		if Diplomacy.cfg.war.casus_belli.has(war.casus_belli):
			cb = str(Diplomacy.cfg.war.casus_belli[war.casus_belli].label).to_lower()
		lines.append("%s declared it%s." % [a, " on a %s" % cb if cb != "" else ""])
		if not war.goal.is_empty():
			lines.append("%s fought %s." % [a, WarGoal.describe(gs, war.goal)])
		var big := war.battles.duplicate()
		big.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.get("lost", 0.0) > y.get("lost", 0.0))
		for rec: Dictionary in big.slice(0, 3):
			var winner: String = gs.nations[rec.winner].display_name if rec.get("winner", "") != "" and gs.nations.has(rec.winner) else "no one"
			lines.append("The battle of %s (%s): won by %s." % [rec.get("name", "?"), rec.get("date", ""), winner])
		lines.append("%d battles; %s lost %s men, %s lost %s." % [war.battles.size(), a, Fmt.people(war.losses.get(war.a, 0.0)), b, Fmt.people(war.losses.get(war.b, 0.0))])
		if war.active():
			lines.append("The war goes on.")
		elif not war.peace.is_empty():
			lines.append("Peace in %s: %s." % [war.end_date, "a white peace" if war.peace.white else "%s took %s" % [gs.nations[war.peace.taker].display_name, "; ".join(war.peace.terms)]])
		out.append({"title": "%s and %s, %s%s" % [a, b, war.start_date, "" if war.active() else " to " + war.end_date], "lines": lines})
	return out


## The changes of owner of a year (0 for all) as lines, in order.
static func territory_lines(gs: Node, year := 0) -> PackedStringArray:
	var out: PackedStringArray = []
	for e: Dictionary in gs.territory_log:
		if year == 0 or e.year == year:
			out.append("%s: %s, %s to %s" % [e.date, MapData.provinces[e.province].name, gs.nations[e.old].display_name if gs.nations.has(e.old) else e.old, gs.nations[e.new].display_name if gs.nations.has(e.new) else e.new])
	return out


## How the nations stand against the start: [{tag, name, provinces, d_provinces, population, d_population, industry, d_industry}],
## the most industrial first.
static func nations_section(gs: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var first: Dictionary = gs.standings_history[0].values if not gs.standings_history.is_empty() else {}
	for r: Dictionary in Standings.ranking(gs, "industry").slice(0, 12):
		var t: String = r.tag
		var then: Dictionary = first.get(t, {})
		out.append({"tag": t, "name": gs.nations[t].display_name,
				"provinces": Standings.value(gs, t, "provinces"), "d_provinces": Standings.value(gs, t, "provinces") - then.get("provinces", Standings.value(gs, t, "provinces")),
				"population": Standings.value(gs, t, "population"), "d_population": Standings.value(gs, t, "population") - then.get("population", Standings.value(gs, t, "population")),
				"industry": r.value, "d_industry": r.value - then.get("industry", r.value)})
	return out


## A low-resolution map of who owns what now.
static func map_image(gs: Node, step := 8) -> Image:
	var size: Vector2i = MapData.map_size
	var img := Image.create(size.x / step, size.y / step, false, Image.FORMAT_RGB8)
	var cache := {}
	for y in img.get_height():
		for x in img.get_width():
			var id := MapData.province_at_pixel(Vector2i(x * step + step / 2, y * step + step / 2))
			if not cache.has(id):
				var color := Color(0.1, 0.17, 0.3)
				if id > 0 and id < gs.province_owner.size():
					var owner: String = gs.province_owner[id]
					color = gs.nations[owner].color if gs.nations.has(owner) else Color(0.4, 0.4, 0.4)
				cache[id] = color
			img.set_pixel(x, y, cache[id])
	return img


# --- Writing it up -----------------------------------------------------------------------------

static func title(gs: Node) -> String:
	var n: Nation = gs.get_player()
	return "Europe, %s to %s%s" % [gs.scenario.get("start_date", ["", "", ""])[0], Clock.year, " (as %s)" % n.display_name if n != null else ""]


## The whole book as Markdown.
static func markdown(gs: Node) -> String:
	var out: PackedStringArray = ["# %s" % title(gs), ""]
	for y in years(gs):
		out.append("## %d" % y)
		out.append(year_summary(gs, y))
		out.append("")
		for e: Dictionary in timeline(gs, y):
			out.append("- **%s** (%s) %s" % [e.date, KINDS.get(e.kind, e.kind), e.text])
		out.append("")
	var wars := wars_section(gs)
	if not wars.is_empty():
		out.append("## The wars")
		for w: Dictionary in wars:
			out.append("### %s" % w.title)
			for l in w.lines:
				out.append("- %s" % l)
			out.append("")
	var lines := territory_lines(gs)
	if not lines.is_empty():
		out.append("## Changes of the map")
		for l in lines:
			out.append("- %s" % l)
		out.append("")
	out.append("## The nations")
	out.append("| Nation | Provinces | People | Industry |")
	out.append("|---|---|---|---|")
	for n: Dictionary in nations_section(gs):
		out.append("| %s | %d (%+d) | %s (%s) | %.1f (%+.1f) |" % [n.name, n.provinces, n.d_provinces, Fmt.people(n.population), _signed_people(n.d_population), n.industry, n.d_industry])
	return "\n".join(out) + "\n"


static func _signed_people(v: float) -> String:
	return ("+" if v >= 0.0 else "-") + Fmt.people(absf(v))


## The whole book as one HTML page (the map of the end as a picture inside it).
static func html(gs: Node, with_map := true) -> String:
	var body := markdown(gs)
	var out: PackedStringArray = ["<!doctype html><html><head><meta charset=\"utf-8\"><title>%s</title>" % _esc(title(gs)),
			"<style>body{font-family:Georgia,serif;max-width:46em;margin:2em auto;padding:0 1em;line-height:1.5;color:#222}h1,h2,h3{font-family:Georgia,serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.2em .6em}img{max-width:100%}</style></head><body>"]
	if with_map:
		var png := map_image(gs).save_png_to_buffer()
		out.append("<img alt=\"Europe at the end\" src=\"data:image/png;base64,%s\">" % Marshalls.raw_to_base64(png))
	var in_list := false
	var in_table := false
	for line in body.split("\n"):
		if line.begins_with("- "):
			if not in_list:
				out.append("<ul>")
				in_list = true
			out.append("<li>%s</li>" % _inline(line.substr(2)))
			continue
		if in_list:
			out.append("</ul>")
			in_list = false
		if line.begins_with("|"):
			if line.contains("---|"):
				continue
			if not in_table:
				out.append("<table>")
				in_table = true
			var cells := line.trim_prefix("|").trim_suffix("|").split("|")
			var tag := "th" if out[out.size() - 1] == "<table>" else "td"
			out.append("<tr>%s</tr>" % "".join(Array(cells).map(func(c: String) -> String: return "<%s>%s</%s>" % [tag, _esc(c.strip_edges()), tag])))
			continue
		if in_table:
			out.append("</table>")
			in_table = false
		if line.begins_with("### "):
			out.append("<h3>%s</h3>" % _esc(line.substr(4)))
		elif line.begins_with("## "):
			out.append("<h2>%s</h2>" % _esc(line.substr(3)))
		elif line.begins_with("# "):
			out.append("<h1>%s</h1>" % _esc(line.substr(2)))
		elif line.strip_edges() != "":
			out.append("<p>%s</p>" % _inline(line))
	if in_list:
		out.append("</ul>")
	if in_table:
		out.append("</table>")
	out.append("</body></html>")
	return "\n".join(out)


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


## Escapes a line and turns **bold** into <b>.
static func _inline(s: String) -> String:
	var parts := _esc(s).split("**")
	var out := ""
	for i in parts.size():
		out += parts[i]
		if i < parts.size() - 1:
			out += "<b>" if i % 2 == 0 else "</b>"
	return out


## Where an export goes: user://history/<scenario>_<date>.<extension>.
static func export_path(gs: Node, extension: String) -> String:
	var name := ("%s_%d_%02d_%02d" % [gs.scenario_dir.trim_suffix("/").get_file(), Clock.year, Clock.month, Clock.day]).validate_filename()
	return "user://history/%s.%s" % [name, extension]


## Writes the book to disk as "md" or "html". Returns the path, or "" on failure.
static func export(gs: Node, extension: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://history")
	var path := export_path(gs, extension)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(markdown(gs) if extension == "md" else html(gs))
	f.close()
	return path
