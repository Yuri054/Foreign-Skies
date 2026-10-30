class_name AIFocus
extends RefCounted
## An AI nation with no focus in hand takes up the one it likes best from those it can start.
## The score is the focus's `ai` weight in data/focus.json, raised by what the nation needs: a
## nation at war likes army and construction foci, one at peace likes income and factories;
## a focus with a min_aggression is left to nations at least that aggressive. Repeatable foci wait until the rest of the
## tree is done or out of reach.


static func step(gs: Node, tag: String) -> void:
	var n: Nation = gs.nations[tag]
	if not n.focus.is_empty() or n.provinces.is_empty():
		return
	# The tree first; a repeatable focus only once nothing else can be started.
	var best := ""
	for repeatable: bool in [false, true]:
		var best_score := 0.0
		for f: Dictionary in Focus.tree_of(tag):
			if bool(f.get("repeatable", false)) != repeatable or Focus.block(gs, tag, f.id) != "":
				continue
			var score := score_of(gs, tag, f)
			if score > best_score + 0.000001:
				best = f.id
				best_score = score
		if best != "":
			break
	if best != "":
		gs.issue_quiet(SetFocus.new(tag, best))


static func score_of(gs: Node, tag: String, f: Dictionary) -> float:
	if f.has("min_aggression") and float(AI.temperament(gs, tag).aggression) < float(f.min_aggression):
		return 0.0
	var fx: Dictionary = f.effects
	var score := float(f.ai)
	var at_war: bool = not gs.wars_of(tag).is_empty()
	if at_war and (fx.has("army_size") or fx.has("cp") or fx.has("war_support")):
		score += 1.0
	if not at_war and (fx.has("income") or fx.has("civilian_factories")):
		score += 0.5
	if fx.has("claim") and not at_war:
		score += 0.3
	# Cheaper foci first among equals.
	return score - float(f.days) / 1000.0
