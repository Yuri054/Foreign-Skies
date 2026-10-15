extends SceneTree
## Headless test for army groups: creating, joining, leaving, the marshal's bonus, pruning and
## saving. Run: godot --headless --path . -s res://tests/army_group_test.gd

var _failures := 0
var gs: Node
var Mil
var UnitC
var CreateC
var JoinC
var MarshalC
var DisbandC
var AssignGeneralC
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
	CreateC = load("res://scripts/sim/create_army_group.gd")
	JoinC = load("res://scripts/sim/assign_to_group.gd")
	MarshalC = load("res://scripts/sim/set_marshal.gd")
	DisbandC = load("res://scripts/sim/disband_army_group.gd")
	AssignGeneralC = load("res://scripts/sim/assign_general.gd")
	SaveGame = load("res://scripts/sim/save_game.gd")

	_test_groups()
	_test_marshal()
	_test_prune()
	_test_save()

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.player_tag = "FRA"


func _army(tag: String, name: String):
	var province := 0
	for a in gs.armies.values():
		if a.tag == tag:
			province = a.province
			break
	var a = Mil.new_army(gs, tag, name, province)
	a.units.append(UnitC.new("infantry"))
	return a


func _ids(list: Array) -> Array[int]:
	var out: Array[int] = []
	for a in list:
		out.append(a.id)
	return out


func _test_groups() -> void:
	_fresh()
	var a = _army("FRA", "A")
	var b = _army("FRA", "B")
	var c = _army("FRA", "C")
	var foreign = _army("GER", "G")
	var make = CreateC.new("FRA", "First", _ids([a, b]))
	_check(gs.issue(make), "a group is created from two armies")
	var grp = gs.army_groups[make.group_id]
	_check(grp.army_ids.size() == 2 and a.group_id == grp.id and b.group_id == grp.id, "both armies belong to it")
	_check(not gs.issue(CreateC.new("FRA", "Bad", _ids([c, foreign]))), "another nation's army cannot be grouped")
	_check(c.group_id == 0 and gs.army_groups.size() == 1, "a refused group changes nothing")

	_check(gs.issue(JoinC.new("FRA", grp.id, _ids([c]))), "an army joins the group")
	_check(grp.army_ids.size() == 3, "the group has three armies")
	var second = CreateC.new("FRA", "", _ids([c]))
	_check(gs.issue(second), "an army can move to a new group")
	_check(grp.army_ids.size() == 2 and c.group_id == second.group_id, "it leaves the old one")
	_check(gs.army_groups[second.group_id].display_name != "", "an unnamed group gets a name")

	_check(gs.issue(JoinC.new("FRA", 0, _ids([a]))), "group 0 takes an army out of its group")
	_check(a.group_id == 0 and grp.army_ids == ([b.id] as Array[int]), "only the other army is left")
	_check(not gs.issue(JoinC.new("GER", grp.id, _ids([foreign]))), "a nation cannot join another's group")

	_check(gs.issue(DisbandC.new("FRA", grp.id)), "a group is disbanded")
	_check(b.group_id == 0 and not gs.army_groups.has(grp.id), "its armies are free")


func _test_marshal() -> void:
	_fresh()
	var a = _army("FRA", "A")
	var b = _army("FRA", "B")
	var make = CreateC.new("FRA", "Group", _ids([a, b]))
	gs.issue(make)
	var grp = gs.army_groups[make.group_id]
	var base: float = a.power()
	var marshal = Mil.new_general(gs, "FRA", "Marshal", 1.2)
	var lead = Mil.new_general(gs, "FRA", "Leader", 1.1)
	Mil.set_general(gs, lead, b)

	_check(not gs.issue(MarshalC.new("FRA", grp.id, lead.id)), "a general who leads an army cannot be marshal")
	_check(gs.issue(MarshalC.new("FRA", grp.id, marshal.id)), "a pool general becomes marshal")
	_check(marshal.group_id == grp.id and grp.marshal_id == marshal.id, "marshal and group agree")
	_check(not Mil.pool_of(gs, "FRA").has(marshal), "a marshal is not in the pool")
	_check(not gs.issue(AssignGeneralC.new("FRA", marshal.id, a.id)), "a marshal cannot also lead an army")
	var expect: float = 1.0 + 0.2 * float(Mil.cfg.army_group.marshal_share)
	_check(absf(a.power() / base - expect) < 0.0001, "the marshal lifts the army's power by his share (%.3f)" % expect)
	var other = _army("FRA", "Outside")
	var outside_base: float = other.power()
	_check(absf(other.power() - outside_base) < 0.0001 and other.group_id == 0, "armies outside the group are unchanged")

	_check(gs.issue(MarshalC.new("FRA", grp.id, 0)), "the marshal can be relieved")
	_check(marshal.group_id == 0 and absf(a.power() - base) < 0.0001, "he returns to the pool and the bonus goes")
	_check(not gs.issue(MarshalC.new("FRA", grp.id, 0)), "relieving an empty post is refused")


func _test_prune() -> void:
	_fresh()
	var a = _army("FRA", "A")
	var b = _army("FRA", "B")
	var make = CreateC.new("FRA", "Group", _ids([a, b]))
	gs.issue(make)
	var grp = gs.army_groups[make.group_id]
	var marshal = Mil.new_general(gs, "FRA", "Marshal", 1.2)
	gs.issue(MarshalC.new("FRA", grp.id, marshal.id))

	gs.armies.erase(a.id)
	Mil.prune_groups(gs)
	_check(grp.army_ids == ([b.id] as Array[int]), "a lost army leaves its group")
	gs.armies.erase(b.id)
	Mil.prune_groups(gs)
	_check(not gs.army_groups.has(grp.id), "an empty group is dissolved")
	_check(marshal.group_id == 0, "its marshal is freed")


func _test_save() -> void:
	_fresh()
	var a = _army("FRA", "A")
	var make = CreateC.new("FRA", "Saved", _ids([a]))
	gs.issue(make)
	var marshal = Mil.new_general(gs, "FRA", "Marshal", 1.2)
	gs.issue(MarshalC.new("FRA", make.group_id, marshal.id))
	var path := "user://army_group_test.sav"
	_check(SaveGame.write(gs, path) == "", "the game saves")
	gs.army_groups.clear()
	_check(SaveGame.read(gs, path) == "", "the game loads")
	var grp = gs.army_groups.get(make.group_id)
	_check(grp != null and grp.marshal_id == marshal.id and grp.army_ids == ([a.id] as Array[int]), "the group survives a save")
	_check(gs.armies[a.id].group_id == make.group_id, "the army still knows its group")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
