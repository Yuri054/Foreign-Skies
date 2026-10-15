extends SceneTree
## Headless test for generals as characters: the starting pool, AssignGeneral, merging, orphans,
## and saving. Run: godot --headless --path . -s res://tests/generals_test.gd

var _failures := 0
var gs: Node
var Mil
var UnitC
var AssignC
var MergeC
var SaveGame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	AssignC = load("res://scripts/sim/assign_general.gd")
	MergeC = load("res://scripts/sim/merge_armies.gd")
	SaveGame = load("res://scripts/sim/save_game.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)

	_test_pool()
	_test_assign()
	_test_merge_and_orphans()
	_test_save()

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _led(tag: String) -> Array:
	var out := []
	for a in gs.armies.values():
		if a.tag == tag and a.general_id != 0:
			out.append(a)
	return out


func _test_pool() -> void:
	var listed: int = Mil.cfg.generals["GER"].size()
	var mine := 0
	for g in gs.generals.values():
		if g.tag == "GER":
			mine += 1
	_check(mine == listed, "every listed German general is a character (%d)" % listed)
	for a in _led("GER"):
		var g = gs.generals[a.general_id]
		_check(g.army_id == a.id and a.general_name == g.display_name and a.general_skill == g.skill,
				"%s and %s agree on who leads whom" % [a.display_name, g.display_name])
	var pool: Array = Mil.pool_of(gs, "GER")
	for g in pool:
		_check(g.army_id == 0, "%s is in the pool" % g.display_name)


func _test_assign() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var armies := _led("FRA")
	_check(armies.size() >= 2, "France has two led armies")
	var a = armies[0]
	var b = armies[1]
	var ga = gs.generals[a.general_id]
	var gb = gs.generals[b.general_id]
	var skill_a: float = a.general_skill

	_check(not gs.issue(AssignC.new("GER", ga.id, b.id)), "a nation cannot use another's general")
	_check(not gs.issue(AssignC.new("FRA", ga.id, a.id)), "assigning a general to his own army changes nothing")

	_check(gs.issue(AssignC.new("FRA", ga.id, b.id)), "a general can take over another army")
	_check(b.general_id == ga.id and a.general_id == 0, "he leaves his old army empty-handed")
	_check(gb.army_id == 0 and a.general_skill == 1.0, "the replaced general is in the pool, the empty army fights at 1.0")
	_check(b.general_skill == skill_a, "the army takes the new general's skill")

	_check(gs.issue(AssignC.new("FRA", gb.id, a.id)), "a pool general takes the empty army")
	_check(gs.issue(AssignC.new("FRA", gb.id, 0)), "army 0 sends a general back to the pool")
	_check(a.general_id == 0 and gb.army_id == 0, "the army is left without one")
	_check(not gs.issue(AssignC.new("FRA", gb.id, 0)), "a general already in the pool cannot be released")


func _test_merge_and_orphans() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var tag := "GER"
	var province := 0
	for a in gs.armies.values():
		if a.tag == tag:
			province = a.province
			break
	var x = Mil.new_army(gs, tag, "X", province)
	var y = Mil.new_army(gs, tag, "Y", province)
	x.units.append(UnitC.new("infantry"))
	y.units.append(UnitC.new("infantry"))
	var weak = Mil.new_general(gs, tag, "Weak", 0.9)
	var strong = Mil.new_general(gs, tag, "Strong", 1.2)
	Mil.set_general(gs, weak, x)
	Mil.set_general(gs, strong, y)
	_check(gs.issue(MergeC.new(tag, [x.id, y.id] as Array[int])), "the armies merge")
	_check(x.general_id == strong.id and strong.army_id == x.id, "the better general leads the merged army")
	_check(weak.army_id == 0, "the other returns to the pool")

	# With the player in charge of this nation nothing re-commands for him.
	gs.player_tag = tag
	gs.armies.erase(x.id)
	Mil.release_orphan_generals(gs)
	_check(strong.army_id == 0, "a general whose army is gone is released")
	# The AI puts a free general back in charge of an army without one.
	gs.player_tag = "FRA"
	var z = Mil.new_army(gs, tag, "Z", province)
	z.units.append(UnitC.new("infantry"))
	Mil.release_orphan_generals(gs)
	_check(strong.army_id != 0 and gs.armies[strong.army_id].general_id == strong.id, "an AI nation re-commands its armies")
	gs.player_tag = tag
	var spare = Mil.new_general(gs, tag, "Spare", 1.5)
	Mil.release_orphan_generals(gs)
	_check(spare.army_id == 0, "the player's free generals stay in the pool")


func _test_save() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var count: int = gs.generals.size()
	var next: int = gs.next_general_id
	var path := "user://generals_test.sav"
	var err: String = SaveGame.write(gs, path)
	_check(err == "", "the game saves")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.generals.clear()
	var result = SaveGame.read(gs, path)
	_check(result == "", "the game loads")
	_check(gs.generals.size() == count and gs.next_general_id == next, "generals survive a save (%d)" % count)
	var good := true
	for g in gs.generals.values():
		if g.army_id != 0 and gs.armies[g.army_id].general_id != g.id:
			good = false
	_check(good, "every loaded general still matches his army")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
