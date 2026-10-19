extends SceneTree
## Headless test of the cities' aura: a city a nation holds lifts the nation's own provinces
## around it (a capital most, fading with distance), an enemy's ground and a captured city get
## nothing, and armies in the aura recover morale and reinforce faster and are supplied farther.
## Run: godot --headless --path . -s res://tests/city_aura_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Mil = load("res://scripts/sim/military.gd")
	gs.ai_enabled = false
	var by_name := {}
	for c in gs.cities:
		by_name[c.name] = c
	var paris: int = by_name.Paris.province
	_check(Mil.city_aura(gs, "FRA", paris) == 1.0, "a capital's own province has the full aura")
	var ring := 0
	var weaker := true
	for nb in Mil.neighbors(paris):
		if gs.province_owner[nb] == "FRA":
			ring += 1
			var a: float = Mil.city_aura(gs, "FRA", nb)
			weaker = weaker and a > 0.0 and a < 1.0
	_check(ring > 0 and weaker, "next to it the aura is weaker but there (%d provinces)" % ring)
	var far := 0
	for id in gs.nations["FRA"].provinces:
		if Mil.city_aura(gs, "FRA", id) == 0.0:
			far += 1
	_check(far >= 5, "far from any city there is none (%d provinces)" % far)
	_check(Mil.city_aura(gs, "GER", paris) == 0.0, "another nation gets nothing from it")
	var great: float = Mil.city_aura(gs, "GBR", by_name.Manchester.province)
	var large: float = Mil.city_aura(gs, "GBR", by_name.Leeds.province)
	_check(great >= 0.6 and large >= 0.35 and great < 1.0, "a great city's aura is below a capital's, a large one's below that (%.2f, %.2f)" % [great, large])
	# A captured city lifts nothing for its owner.
	gs.set_controller(paris, "GER")
	clock.advance_day()
	_check(Mil.city_aura(gs, "FRA", paris) == 0.0, "a captured capital gives its nation nothing")
	gs.set_controller(paris, "FRA")
	clock.advance_day()
	# Supply reaches one hop farther in the aura.
	var limit: float = Mil.cfg.supply.range
	_check(is_equal_approx(Mil.cfg.cities.supply_range, 1.0) and limit > 0.0, "the aura adds a hop to the supply range at full strength")
	# Morale recovers faster in the aura than away from it.
	var home: Variant = null
	var away: Variant = null
	for a in gs.armies.values():
		if a.tag == "FRA":
			if Mil.city_aura(gs, "FRA", a.province) == 0.0 and away == null:
				away = a
	_check(away != null, "France has an army outside the aura")
	for a in gs.armies.values():
		if a.tag == "FRA" and a != away:
			home = a
			break
	home.province = paris
	home.path.clear()
	away.path.clear()
	for army in [home, away]:
		army.fighting = false
		for u in army.units:
			u.morale = 0.2
	clock.advance_day()
	var m_home: float = home.units[0].morale
	var m_away: float = away.units[0].morale
	_check(m_home > m_away, "an army in the capital recovers morale faster (%.3f against %.3f)" % [m_home, m_away])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
