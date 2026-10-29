class_name Front
extends RefCounted
## A front: the provinces the player wants held (the border with a nation, or a hand-drawn
## chain of adjacent provinces), with armies assigned to it.
## Each day Military.step_fronts spreads the assigned armies along the line, by strength,
## and sends idle ones to their province.

var id := 0
var tag := ""
var display_name := ""
## Nation this front faces ("" for a hand-drawn line). The line is then every province the
## owner holds that touches ground held by that nation, and follows the war as it moves.
var against := ""
## For a border front: a province the player clicked to hold only the stretch of that border around it (0: the whole
## border). The line is the stretch nearest to it as the border moves (Military.border_stretch).
var anchor := 0
## The provinces of the line (a hand-drawn line is a chain: each borders the next).
var provinces: Array[int] = []
var army_ids: Array[int] = []
## Provinces of the line the armies gather on instead of spreading along all of it (empty: the whole line).
## Armies massed on a few key provinces fight as stacks; the AI sets these (see AIDefense).
var anchors: Array[int] = []
## army id -> province it should hold.
var slots: Dictionary = {}
## Set when the line or the assigned armies changed and the slots must be dealt again.
## The GameState.control_version the line was last read at (-1: not yet).
var line_stamp := -1
var dirty := true
## Army id -> the day before which no route to its slot is looked for again (it found none).
var retry: Dictionary = {}
## "line" (a border with a nation, or a chain drawn by hand; one touching no enemy is a fallback line, see
## is_fallback) or "garrison" (provinces picked one by one, not joined: ports, cities, the capital, to guard).
var kind := "line"
## Whether the armies on it spread their divisions along the line as detachments (FrontSolver); off, each army holds
## one province (the slots). The player's fronts spread; the AI's do not yet.
var spread := false
## How far a division may be sent along the line to fill a gap: "rigid", "balanced" or "flexible" (FrontSolver._reach).
var cohesion := "balanced"
## The line in order along its length, the weight of each of its provinces, and the day they were weighed (FrontSolver).
var order: Array[int] = []
var weights: Array[float] = []
var weights_day := -1
## Army ids still deploying: newly put on the front, they go anywhere along the line until every province has its
## share; only then does the cohesion limit hold them (FrontSolver).
var deploying: Dictionary = {}
## Each army's sector of the ordered line on a broad front: army id -> Vector2i(first index, one past the last).
var sectors: Dictionary = {}
## Each army's colour on the map (army id -> index into ArmyLayer.ARMY_COLORS), kept while it stays on the front, so an
## army joining or leaving does not repaint the others (FrontSolver.keep_colours).
var colours: Dictionary = {}


## A line drawn in the nation's own ground that touches no enemy: the armies on it dig in deeper and faster
## (FrontSolver, military.json fronts fallback_*). It turns into a fighting front when an enemy comes up to it.
func is_fallback(gs: Node) -> bool:
	if kind != "line" or not against.is_empty():
		return false
	for p in provinces:
		for n: int in Military.neighbors(p):
			var holder: String = gs.province_controller[n]
			if holder != tag and gs.at_war(tag, holder):
				return false
	return true


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "name": display_name, "against": against, "provinces": provinces, "armies": army_ids}
