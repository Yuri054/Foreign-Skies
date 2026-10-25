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


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "name": display_name, "against": against, "provinces": provinces, "armies": army_ids}
