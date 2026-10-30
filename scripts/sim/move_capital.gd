class_name MoveCapital
extends Command
## The player's answer when its capital falls (Capitulation): the city the government moves to. Only one of the cities
## offered in GameState.capital_choice can be chosen.

var tag: String
var province: int


func _init(p_tag := "", p_province := 0) -> void:
	tag = p_tag
	province = p_province


func execute(gs: Node) -> bool:
	var choice: Dictionary = gs.capital_choice
	if choice.get("tag", "") != tag or province not in choice.get("candidates", []):
		return false
	if gs.province_controller[province] != tag:
		return false
	Capitulation.move_capital(gs, tag, province)
	return true


func changes_economy() -> bool:
	return false


func to_dict() -> Dictionary:
	return {"type": "MoveCapital", "tag": tag, "province": province}
