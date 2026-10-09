class_name Command
extends RefCounted
## A player or AI action. All state changes from outside the simulation go through
## GameState.issue(), which keeps a log (for save/load and tests).


## Applies the action. Returns false if it was rejected and changed nothing.
func execute(_gs: Node) -> bool:
	return false


## Whether the command can change the economy's figures, so that GameState.issue_quiet marks
## them for a recompute. Orders to armies, fronts and diplomats cannot.
func changes_economy() -> bool:
	return true


## Plain data for saving the command log.
func to_dict() -> Dictionary:
	return {}
