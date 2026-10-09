class_name Command
extends RefCounted
## A player or AI action. All state changes from outside the simulation go through
## GameState.issue(), which keeps a log (for save/load and tests).


## Applies the action. Returns false if it was rejected and changed nothing.
func execute(_gs: Node) -> bool:
	return false


## Plain data for saving the command log.
func to_dict() -> Dictionary:
	return {}
