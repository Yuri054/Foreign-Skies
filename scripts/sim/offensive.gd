class_name Offensive
extends RefCounted
## An army's plan of attack (docs/FRONTLINES.md, stage F5): a broad push toward a target line, or a spearhead at one
## province, in phases (line A, then line B...). While it is planned the army's stacks on their front build up
## planning; launched, they attack as aggressively as it says. The rules are Offensives'.

var id := 0
var tag := ""
## The army (not a detachment) whose plan it is.
var army_id := 0
## "broad" (every stack pushes toward the target line from where it stands) or "spearhead" (the army gathers and
## strikes at one province after another on the way to the target).
var kind := "broad"
## The objectives in order: each phase is a list of provinces (a target line; a spearhead's is one province).
var phases: Array = []
## The phase being fought for.
var phase := 0
## "careful", "balanced" or "aggressive" (military.json offensive).
var aggressiveness := "balanced"
## Launched (true) or only planned.
var active := false
## Set once the stacks have planned enough for this phase (or straight away when aggressive); the attack goes on until
## the phase is taken, then plans again for the next.
var launched := false
## Every phase taken.
var done := false


## The provinces of the phase being fought for (empty when done).
func targets() -> Array[int]:
	var out: Array[int] = []
	if phase < phases.size():
		for p in phases[phase]:
			out.append(int(p))
	return out


func to_dict() -> Dictionary:
	return {"id": id, "tag": tag, "army": army_id, "kind": kind, "phases": phases, "phase": phase,
			"aggressiveness": aggressiveness, "active": active, "done": done}
