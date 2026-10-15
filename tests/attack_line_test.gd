extends SceneTree
## Headless test for attack lines: drawing one, starting and stopping it, taking ground with a
## group's armies, the front it leaves from, ending with the war, and saving.
## Run: godot --headless --path . -s res://tests/attack_line_test.gd

var _failures := 0
var gs: Node
var clock: Node
var Mil
var UnitC
var GroupC
var LineC
var SetC
var DeleteC
var FrontC
var AssignC
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
	clock = root.get_node("Clock")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	GroupC = load("res://scripts/sim/create_army_group.gd")
	LineC = load("res://scripts/sim/create_attack_line.gd")
	SetC = load("res://scripts/sim/set_attack_line.gd")
	DeleteC = load("res://scripts/sim/delete_attack_line.gd")
	FrontC = load("res://scripts/sim/designate_front.gd")
	AssignC = load("res://scripts/sim/assign_to_front.gd")
	SaveGame = load("res://scripts/sim/save_game.gd")

	_test_commands()
	_test_attack()
	_test_front_and_stop()
	_test_war_ends()
	_test_save()

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.armies.clear()
	for tag in gs.nations:
		gs.nations[tag].recruiting.clear()
	Mil.refresh_men(gs)
	gs.set_player("GER")


func _army(tag: String, province: int, infantry: int):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	return a


func _pair() -> Array:
	for p: int in Mil.border_provinces(gs, "GER", "BEL"):
		for n: int in Mil.neighbors(p):
			if gs.province_controller[n] == "BEL":
				return [p, n]
	return []


## Three big German armies on the border, grouped, and a weak Belgian one far away.
func _setup() -> Array:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	var ids: Array[int] = []
	for i in 3:
		ids.append(_army("GER", pair[0], 10).id)
	_army("BEL", gs.nations["BEL"].capital, 1)
	var make = GroupC.new("GER", "Western Group", ids)
	gs.issue(make)
	return [pair, make.group_id, ids]


func _step(days: int) -> void:
	for i in days:
		clock.days_elapsed += 1
		Mil.step_day(gs)


func _held_from(tag: String, owner: String) -> int:
	var n := 0
	for id: int in gs.nations[owner].provinces:
		if gs.province_controller[id] == tag:
			n += 1
	return n


func _test_commands() -> void:
	var s := _setup()
	var group: int = s[1]
	var make = LineC.new("GER", group, "BEL")
	_check(gs.issue(make), "an attack line is drawn")
	var line = gs.attack_lines[make.line_id]
	_check(not line.active, "it starts switched off")
	_check(not gs.issue(LineC.new("GER", group, "FRA")), "a group has only one line")
	_check(not gs.issue(LineC.new("FRA", group, "BEL")), "a nation cannot use another's group")
	_check(not gs.issue(LineC.new("GER", 999, "BEL")), "a line needs a real group")
	_check(not gs.issue(SetC.new("FRA", line.id, true)), "a nation cannot start another's line")
	_check(gs.issue(SetC.new("GER", line.id, true)) and line.active, "the line is started")
	_check(not gs.issue(SetC.new("GER", line.id, true)), "starting it twice is refused")
	_check(gs.issue(SetC.new("GER", line.id, false)) and not line.active, "the line is stopped")
	gs.wars.clear()
	_check(not gs.issue(SetC.new("GER", line.id, true)), "a line cannot start without a war")
	_check(gs.issue(DeleteC.new("GER", line.id)) and gs.attack_lines.is_empty(), "the line is deleted")


func _test_attack() -> void:
	var s := _setup()
	var make = LineC.new("GER", s[1], "BEL")
	gs.issue(make)
	var before := _held_from("GER", "BEL")
	_step(10)
	_check(_held_from("GER", "BEL") == before, "an idle line does nothing")
	gs.issue(SetC.new("GER", make.line_id, true))
	_step(60)
	var line = gs.attack_lines[make.line_id]
	_check(_held_from("GER", "BEL") > before, "the group takes ground from a weak neighbour (%d provinces)" % _held_from("GER", "BEL"))
	_check(not gs.ai_campaign.has("GER"), "the attack does not use the AI's campaign slot")
	_check(line.active, "the line is still on")


func _test_front_and_stop() -> void:
	var s := _setup()
	var pair: Array = s[0]
	var ids: Array[int] = s[2]
	var front = FrontC.new("GER", "Belgian front", [] as Array[int], "BEL")
	_check(gs.issue(front), "a border front is drawn")
	gs.issue(AssignC.new("GER", front.front_id, ids))
	var make = LineC.new("GER", s[1], "BEL", front.front_id)
	gs.issue(make)
	var line = gs.attack_lines[make.line_id]
	gs.issue(SetC.new("GER", make.line_id, true))
	_step(3)
	_check(not line.campaign.is_empty(), "a campaign starts from the front's line")
	var sent: Array = line.campaign.armies
	_check(not sent.is_empty() and gs.armies[sent[0]].front_id == 0, "the armies sent leave the front")
	_check(gs.province_controller[line.campaign.target] == "BEL", "the target is Belgian ground")
	gs.issue(SetC.new("GER", make.line_id, false))
	_check(line.campaign.is_empty() and not line.active, "stopping ends the campaign")
	_check(gs.armies[sent[0]].front_id == front.front_id, "the armies go back to the front")
	for id in sent:
		_check(gs.armies[id].path.is_empty(), "no army is left marching")


func _test_war_ends() -> void:
	var s := _setup()
	var make = LineC.new("GER", s[1], "BEL")
	gs.issue(make)
	gs.issue(SetC.new("GER", make.line_id, true))
	_step(3)
	gs.set_war("GER", "BEL", false)
	_step(2)
	_check(not gs.attack_lines[make.line_id].active, "a line ends when the war does")
	for id in s[2]:
		if gs.armies.has(id):
			_check(gs.armies[id].path.is_empty(), "the armies stand down")
	gs.issue(GroupC.new("GER", "Other", [s[2][0]] as Array[int]))
	_check(gs.attack_lines.has(make.line_id), "moving an army to another group keeps the old line")
	gs.issue(load("res://scripts/sim/disband_army_group.gd").new("GER", s[1]))
	_step(1)
	_check(not gs.attack_lines.has(make.line_id), "a line goes with its group")


func _test_save() -> void:
	var s := _setup()
	var make = LineC.new("GER", s[1], "BEL")
	gs.issue(make)
	gs.issue(SetC.new("GER", make.line_id, true))
	_step(3)
	var campaign: Dictionary = gs.attack_lines[make.line_id].campaign
	var target: int = campaign.get("target", 0)
	var path := "user://attack_line_test.sav"
	_check(SaveGame.write(gs, path) == "", "the game saves")
	gs.attack_lines.clear()
	_check(SaveGame.read(gs, path) == "", "the game loads")
	var line = gs.attack_lines.get(make.line_id)
	_check(line != null and line.active and line.enemy == "BEL", "the line survives a save")
	_check(line != null and line.campaign.get("target", -1) == target and target != 0, "so does its campaign")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
