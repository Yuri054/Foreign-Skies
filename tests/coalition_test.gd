extends SceneTree
## Headless test for coalition AI: allies keep off each other's targets, a nation stays in the war with its allies unless it is
## strained, allies that all want peace take it together, and a nation with a partner that cannot speak for itself (the player)
## stays bound.
## Run: godot --headless --path . -s res://tests/coalition_test.gd

var _failures := 0
var gs: Node
var K
var D
var C
var AP
var hold_on := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


## Germany and Austria-Hungary at war with France in one conflict; each holds some French ground.
func _war(player := "ESP") -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_campaign.clear()
	gs.ai_campaign_extra.clear()
	gs.set_player(player)
	gs.ai_enabled = false
	gs.set_war("GER", "FRA", true, "none")
	var group: int = gs.war_between("GER", "FRA").war_group
	gs.set_war("AUH", "FRA", true, "ally_called", group)
	D._open_group(gs, "GER", "FRA", group)
	D._open_group(gs, "AUH", "FRA", group)
	var fra: Array = gs.nations["FRA"].provinces.duplicate()
	for i in 4:
		gs.province_controller[fra[i]] = "GER"
	for i in 3:
		gs.province_controller[fra[4 + i]] = "AUH"
	AI_cfg_hold(hold_on)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	K = load("res://scripts/ai/ai_coalition.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	C = load("res://scripts/sim/conference.gd")
	AP = load("res://scripts/ai/ai_peace.gd")
	var AO = load("res://scripts/ai/ai_offense.gd")
	var Peace = load("res://scripts/sim/peace.gd")

	# --- Targets --------------------------------------------------------------------------------
	_war()
	gs.ai_campaign["GER"] = {"enemy": "FRA", "target": 777, "staging": 1, "armies": [], "phase": "gather", "started": 0}
	_check(K.claimed(gs, "AUH").has(777) and K.claimed(gs, "AUH")[777] == "GER", "a province Germany aims at is claimed against Austria-Hungary")
	_check(not K.claimed(gs, "GER").has(777), "but not against Germany itself")
	_check(K.claimed(gs, "ESP").is_empty(), "and nothing is claimed against a nation that fights no one")

	# --- Holding (a setting that is off in Historical: these tests turn it on) --------------------------------
	hold_on = true
	_war()
	var war: War = gs.war_between("GER", "FRA")
	gs.nations["GER"].war_support = 70.0
	_check(K.hold(gs, "GER", war), "a nation with allies fighting on stays in the war")
	gs.nations["GER"].war_support = 20.0
	_check(not K.hold(gs, "GER", war) and K.strained(gs, "GER", war), "unless its people have lost heart")
	gs.nations["GER"].war_support = 70.0
	gs.province_controller[gs.nations["GER"].capital] = "FRA"
	_check(not K.hold(gs, "GER", war), "or its capital is lost")
	gs.province_controller[gs.nations["GER"].capital] = "GER"
	AI_cfg_hold(false)
	_check(not K.hold(gs, "GER", war), "the rule can be switched off in the data")
	AI_cfg_hold(true)
	gs.wars.erase(gs._war_key("AUH", "FRA"))
	_check(not K.hold(gs, "GER", war), "with no ally fighting beside it a nation is free")

	# --- Joint peace ------------------------------------------------------------------------------
	_war()
	war = gs.war_between("GER", "FRA")
	gs.nations["AUH"].war_support = 0.0
	_check(K.joint_partners(gs, "GER", war) == ["AUH"], "an ally that wants peace too joins the proposal (%s)" % str(K.joint_partners(gs, "GER", war)))
	gs.nations["AUH"].war_support = 100.0
	gs.nations["AUH"].treasury = 100.0
	var wars_before: int = gs.wars.size()
	var reluctant: Array = K.joint_partners(gs, "GER", war)
	_check(reluctant.is_empty() or AP.urge(gs, "AUH", gs.war_between("AUH", "FRA")) >= float(AI_cfg("partner_urge")) * float(AP.cfg().seek_threshold), "one that is not ready keeps the others bound")
	_war("AUH")
	war = gs.war_between("GER", "FRA")
	_check(K.joint_partners(gs, "GER", war).is_empty(), "an ally that is the player cannot be spoken for")
	_check(K.hold(gs, "GER", war), "so the nation stays bound to it")

	hold_on = false
	AI_cfg_hold(false)

	# The monthly overtures: both nations want out and France has no will left, so they make peace together.
	_war()
	gs.nations["FRA"].war_support = 0.0
	gs.nations["GER"].war_support = 0.0
	gs.nations["AUH"].war_support = 0.0
	war = gs.war_between("GER", "FRA")
	AP.overtures(gs)
	_check(gs.war_between("GER", "FRA") == null and gs.war_between("AUH", "FRA") == null, "both wars end in one peace")
	_check(gs.history_log.any(func(e: Dictionary) -> bool: return e.text.contains("chaired")), "which was a conference (written into the history)")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func AI_cfg(key: String):
	return root.get_node("GameState").get_script().get_global_name() if false else load("res://scripts/ai/ai.gd").cfg.coalition[key]


func AI_cfg_hold(value: bool) -> bool:
	var ai = load("res://scripts/ai/ai.gd")
	var old: bool = ai.cfg.coalition.hold
	ai.cfg.coalition.hold = value
	return old
