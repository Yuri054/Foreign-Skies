class_name ArmyGroup
extends RefCounted
## Armies of one nation gathered under a field marshal (as an army group in Hearts of Iron).
## Group members fight with a share of the marshal's skill on top of their own general's
## (data/military.json "army_group"). The marshal comes from the nation's pool of generals.

var id := 0
var tag := ""
var display_name := ""
var army_ids: Array[int] = []
## General who commands the group (0 = none).
var marshal_id := 0


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "name": display_name, "armies": army_ids, "marshal": marshal_id}
