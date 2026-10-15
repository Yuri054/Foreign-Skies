class_name General
extends RefCounted
## A commander a nation holds. He is in the pool until the player (or the AI) assigns him to
## an army; his skill then multiplies that army's power (Army.power). The pool of each nation
## comes from "generals" in data/military.json.

var id := 0
var tag := ""
var display_name := ""
var skill := 1.0
## Army he leads (0 = in the pool).
var army_id := 0
## Army group he commands as its marshal (0 = none).
var group_id := 0


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "name": display_name, "skill": skill, "army": army_id, "group": group_id}
