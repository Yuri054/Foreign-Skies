class_name AICoalition
extends RefCounted
## Nations on one side of a war act as a coalition (data/ai.json, coalition). Allies do not aim campaigns at the same province;
## a nation does not make a separate peace while its allies fight on unless it is strained; and the nations of a side that all
## want out make peace together, at a conference (see Conference). Static, like the rest of the AI.


static func cfg() -> Dictionary:
	return AI.cfg.coalition


## The provinces allies of `tag` (on its side, at war with the same enemy) are aiming campaigns at.
static func claimed(gs: Node, tag: String) -> Dictionary:
	var out := {}
	for enemy in AI.enemies(gs, tag):
		for ally in Conference.partners(gs, tag, enemy):
			for c: Dictionary in AIOffense.campaigns(gs, ally):
				if c.enemy == enemy:
					out[c.target] = ally
	return out


## Allies of `tag` fighting `enemy` beside it.
static func partners(gs: Node, tag: String, enemy: String) -> Array[String]:
	return Conference.partners(gs, tag, enemy)


## Whether a nation is too hard pressed to stand by its allies: its people have lost heart, its capital is gone, or it is
## being beaten badly.
static func strained(gs: Node, tag: String, war: War) -> bool:
	var c := cfg()
	var enemy := war.other(tag)
	return gs.nations[tag].war_support <= float(c.strain_support) or Peace.capital_taken_by(gs, tag) == enemy \
			or Peace.war_score(gs, war, tag) <= -float(c.strain_score)


## The allies that would join a peace `tag` proposes: all of those fighting beside it, if every one of them is an AI nation that
## wants peace too; else {} (the nation is then bound to them, or strained and free to go alone).
static func joint_partners(gs: Node, tag: String, war: War) -> Array[String]:
	var out: Array[String] = []
	var enemy := war.other(tag)
	for p in partners(gs, tag, enemy):
		var pw: War = gs.war_between(p, enemy)
		if p == gs.player_tag or pw == null:
			return []
		if AIPeace.urge(gs, p, pw) < float(cfg().partner_urge) * float(AIPeace.cfg().seek_threshold):
			return []
		out.append(p)
	return out


## Whether `tag` should stay in the war rather than make a peace of its own while allies fight on.
static func hold(gs: Node, tag: String, war: War) -> bool:
	if not bool(cfg().hold):
		return false
	if partners(gs, tag, war.other(tag)).is_empty():
		return false
	return not strained(gs, tag, war)
