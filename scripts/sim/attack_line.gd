class_name AttackLine
extends RefCounted
## An offensive order: an army group attacks one enemy along a front (see AttackLines). While
## it is active the group's armies carry out the same campaign the AI runs (AIOffense): pick the
## best enemy province next to the front, gather, advance, and go on while the odds hold.

var id := 0
var tag := ""
var display_name := ""
var group_id := 0
var enemy := ""
## Front whose line the attack leaves from (0 = any border with the enemy). The armies
## return to it when the attack ends.
var front_id := 0
var active := false
## The running campaign, in the form AIOffense uses ({} while none is running).
var campaign: Dictionary = {}
## The day before which no new campaign is looked for (nothing worth attacking was found).
var wait := 0


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "name": display_name, "group": group_id, "enemy": enemy, "front": front_id,
			"active": active}
